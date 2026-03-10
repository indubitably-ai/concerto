defmodule Concerto.Worker do
  @moduledoc false

  alias Concerto.{
    EventLogger,
    RunAttempt,
    RuntimeConstants,
    StateStore,
    TraceContext,
    WorkItem,
    WorkspaceManager
  }

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :work_item).work_item_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(opts) do
    Task.start_link(fn -> run(opts) end)
  end

  def runtime_metadata(%WorkItem{} = work_item, %TraceContext{} = trace) do
    %{
      "work_item_id" => work_item.work_item_id,
      "workspace_key" => work_item.workspace_key,
      "dispatch_revision" => work_item.dispatch_revision,
      "trace_id" => trace.trace_id,
      "span_id" => trace.span_id
    }
  end

  def run(opts) do
    work_item = Keyword.fetch!(opts, :work_item)
    runtime = Keyword.fetch!(opts, :runtime)
    orchestrator = Keyword.fetch!(opts, :orchestrator)
    trace = Keyword.fetch!(opts, :trace)
    run_id = unique_id()
    run_dir = Path.join(runtime.paths.runs_root, run_id)
    File.mkdir_p!(run_dir)

    result =
      with {:ok, workspace} <- WorkspaceManager.ensure_workspace(runtime.workflow.config.workspace.root, work_item.workspace_key),
           :ok <- emit_workspace_event(runtime.paths, workspace, work_item, trace),
           {:ok, materialization} <-
             materialize_workspace(
               runtime.workspace_materializer,
               runtime.workflow.workflow_root,
               work_item.workspace_key,
               workspace.path,
               runtime.paths
             ),
           :ok <- emit_materialization_event(runtime.paths, materialization, work_item, trace),
           prompt <- Concerto.WorkflowLoader.assemble_prompt(runtime.workflow.body, work_item),
           {:ok, result} <- execute_attempt(runtime, work_item, workspace.path, run_id, run_dir, trace, prompt) do
        result
      else
        {:error, reason} -> failure_result(runtime, work_item, trace, run_id, run_dir, reason)
      end

    send(orchestrator, {:worker_finished, work_item.work_item_id, result})
  end

  defp emit_workspace_event(paths, workspace, work_item, trace) do
    event_name = if workspace.created_now, do: :workspace_created, else: :workspace_reused
    EventLogger.emit(paths, event_name, runtime_metadata(work_item, trace), %{"path" => workspace.path})
    :ok
  end

  defp materialize_workspace({module, config}, workflow_root, workspace_key, workspace_path, paths) do
    module.materialize(workflow_root, workspace_key, workspace_path, paths, config)
  end

  defp materialize_workspace(module, workflow_root, workspace_key, workspace_path, paths) do
    module.materialize(workflow_root, workspace_key, workspace_path, paths, %{})
  end

  defp emit_materialization_event(paths, materialization, work_item, trace) do
    event_name = if materialization.materialized_now, do: :workspace_materialized, else: :workspace_materialization_skipped
    EventLogger.emit(paths, event_name, runtime_metadata(work_item, trace), %{"workspace_path" => materialization.workspace_path})
    :ok
  end

  defp execute_attempt(runtime, work_item, workspace_path, run_id, run_dir, trace, prompt) do
    metadata = Map.put(runtime_metadata(work_item, trace), "run_id", run_id)
    started_at = DateTime.utc_now()

    runner_spec = %{
      run_id: run_id,
      work_item: work_item,
      workspace_path: workspace_path,
      workflow_path: runtime.workflow.workflow_path,
      run_dir: run_dir,
      runner_image: runtime.runner_image,
      runner_env: runtime.runner_env,
      runner_auth_mounts: runtime.runner_auth_mounts
    }

    with {:ok, handle} <- start_runtime(runtime.container_runtime, runner_spec),
         :ok <- write_ownership(runtime.paths, run_id, handle, runtime.workflow.workflow_root, work_item),
         :ok <- log_container_launch(runtime.paths, metadata, handle),
         {:ok, session} <-
           run_session(runtime.app_server_client, %{
             handle: handle,
             metadata: metadata,
             prompt: prompt,
             workspace_path: Map.get(handle, :container_workspace_path, workspace_path),
             run_dir: run_dir,
             paths: runtime.paths,
             work_item: work_item,
             trace: trace,
             continue?: fn -> Concerto.DispatchPolicy.continuation_allowed?(runtime.work_source, work_item) end,
             timeout_ms: RuntimeConstants.attempt_timeout_ms(),
             response_timeout_ms: RuntimeConstants.response_timeout_ms()
           }) do
      stop_runtime(runtime.container_runtime, handle)
      StateStore.delete_ownership_manifest(runtime.paths, run_id)

      {:ok,
       %{
         attempt: %RunAttempt{
           run_id: run_id,
           work_item_id: work_item.work_item_id,
           workspace_key: work_item.workspace_key,
           dispatch_revision: work_item.dispatch_revision,
           workspace_path: workspace_path,
           thread_id: session.thread_id,
           last_turn_id: session.last_turn_id,
           turn_count: session.turn_count,
           trace: trace,
           started_at: started_at,
           finished_at: DateTime.utc_now(),
           stop_reason: session.stop_reason,
           status: session.status
         }
       }}
    end
  end

  defp failure_result(runtime, work_item, trace, run_id, workspace_path, reason) do
    EventLogger.emit(
      runtime.paths,
      :attempt_failed,
      Map.put(runtime_metadata(work_item, trace), "run_id", run_id),
      %{"error" => inspect(reason)}
    )

    %{
      attempt: %RunAttempt{
        run_id: run_id,
        work_item_id: work_item.work_item_id,
        workspace_key: work_item.workspace_key,
        dispatch_revision: work_item.dispatch_revision,
        workspace_path: workspace_path,
        thread_id: nil,
        last_turn_id: nil,
        turn_count: 0,
        trace: trace,
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        stop_reason: :startup_failed,
        status: :failed
      }
    }
  end

  defp write_ownership(paths, run_id, handle, workflow_root, work_item) do
    StateStore.write_ownership_manifest(paths, run_id, %{
      "run_id" => run_id,
      "workflow_root" => workflow_root,
      "container_ref" => handle.container_ref,
      "stderr_path" => handle.stderr_path,
      "workspace_path" => handle.workspace_path,
      "work_item_id" => work_item.work_item_id,
      "workspace_key" => work_item.workspace_key
    })
  end

  defp log_container_launch(paths, metadata, handle) do
    EventLogger.emit(paths, :container_launched, metadata, %{"container_ref" => handle.container_ref})
    :ok
  end

  defp start_runtime({module, config}, spec), do: module.start_app_server(spec, config)
  defp start_runtime(module, spec), do: module.start_app_server(spec, %{})

  defp stop_runtime({module, config}, handle), do: module.stop(handle, config)
  defp stop_runtime(module, handle), do: module.stop(handle, %{})

  defp run_session({module, config}, spec), do: module.run_session(spec, config)
  defp run_session(module, spec), do: module.run_session(spec, %{})

  defp unique_id do
    12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
