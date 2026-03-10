defmodule Concerto.Orchestrator do
  @moduledoc false

  use GenServer

  alias Concerto.{DispatchPolicy, EventLogger, StateStore, TraceContext, Worker}

  def start_link(runtime) do
    GenServer.start_link(__MODULE__, runtime, name: __MODULE__)
  end

  @impl true
  def init(runtime) do
    send(self(), :poll)
    {:ok, %{runtime: runtime, running: %{}}}
  end

  @impl true
  def handle_info(:poll, state) do
    state =
      state
      |> reconcile_running()
      |> dispatch_available()

    Process.send_after(self(), :poll, state.runtime.workflow.config.polling.interval_ms)
    {:noreply, state}
  end

  def handle_info({:worker_finished, work_item_id, result}, state) do
    state = update_in(state.running, &Map.delete(&1, work_item_id))
    persist_terminal_state(state.runtime.paths, result)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    {work_item_id, _metadata} =
      Enum.find(state.running, fn {_work_item_id, metadata} -> metadata.pid == pid end) || {nil, nil}

    next_state =
      if work_item_id do
        EventLogger.emit(
          state.runtime.paths,
          :attempt_failed,
          %{"work_item_id" => work_item_id, "error" => inspect(reason)},
          %{}
        )

        update_in(state.running, &Map.delete(&1, work_item_id))
      else
        state
      end

    {:noreply, next_state}
  end

  defp reconcile_running(%{running: running} = state) when map_size(running) == 0, do: state

  defp reconcile_running(state) do
    runtime = state.runtime
    {work_source_module, work_source_config} = runtime.work_source
    work_item_ids = Map.keys(state.running)

    case work_source_module.fetch_work_item_states(work_item_ids, work_source_config) do
      {:ok, rows} ->
        rows_by_id = Map.new(rows, &{&1.work_item_id, &1})

        Enum.reduce(state.running, state, fn {work_item_id, metadata}, acc ->
          case rows_by_id[work_item_id] do
            %{lifecycle_state: :dispatchable, dispatch_revision: revision}
            when revision == metadata.work_item.dispatch_revision ->
              acc

            refreshed_state ->
              EventLogger.emit(
                runtime.paths,
                :reconciliation_stop,
                Worker.runtime_metadata(metadata.work_item, metadata.trace),
                %{"reason" => stop_reason_from_state(refreshed_state)}
              )

              send(metadata.pid, {:concerto_cancel, :reconciliation, refreshed_state})
              acc
          end
        end)

      {:error, reason} ->
        EventLogger.emit(
          runtime.paths,
          :postgres_read_failed,
          %{"scope" => "reconciliation", "error" => inspect(reason)},
          %{}
        )

        state
    end
  end

  defp dispatch_available(state) do
    runtime = state.runtime
    slots = runtime.workflow.config.agent.max_concurrent_agents - map_size(state.running)

    if slots <= 0 do
      state
    else
      {work_source_module, work_source_config} = runtime.work_source

      case work_source_module.fetch_dispatch_candidates(max(slots * 4, slots), work_source_config) do
        {:ok, candidates} ->
          candidates
          |> DispatchPolicy.eligible_candidates(state.running, runtime.paths)
          |> DispatchPolicy.sort_candidates()
          |> Enum.take(slots)
          |> Enum.reduce(state, &start_worker(&1, &2))

        {:error, reason} ->
          EventLogger.emit(
            runtime.paths,
            :postgres_read_failed,
            %{"scope" => "dispatch", "error" => inspect(reason)},
            %{}
          )

          state
      end
    end
  end

  defp start_worker(work_item, state) do
    trace = TraceContext.child(TraceContext.root(), work_item.work_item_id)
    EventLogger.emit(state.runtime.paths, :dispatch_started, Worker.runtime_metadata(work_item, trace), %{})

    case DynamicSupervisor.start_child(
           Concerto.WorkerSupervisor,
           {Worker, [work_item: work_item, runtime: state.runtime, orchestrator: self(), trace: trace]}
         ) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        put_in(state.running[work_item.work_item_id], %{pid: pid, ref: ref, work_item: work_item, trace: trace})

      {:error, reason} ->
        EventLogger.emit(
          state.runtime.paths,
          :attempt_failed,
          %{"work_item_id" => work_item.work_item_id, "error" => inspect(reason)},
          %{}
        )

        state
    end
  end

  defp persist_terminal_state(paths, %{attempt: attempt}) do
    :ok = StateStore.put_terminal_revision(paths, attempt.work_item_id, attempt.dispatch_revision)
    :ok = StateStore.persist_run_attempt(paths, attempt)
  end

  defp stop_reason_from_state(nil), do: "missing"
  defp stop_reason_from_state(%{lifecycle_state: :inactive}), do: "inactive"
  defp stop_reason_from_state(%{lifecycle_state: :terminal}), do: "terminal"
  defp stop_reason_from_state(%{dispatch_revision: _}), do: "dispatch_revision_changed"
end
