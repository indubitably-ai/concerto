defmodule Concerto.AppServerClient.Stdio do
  @moduledoc false

  @behaviour Concerto.AppServerClient

  alias Concerto.EventLogger

  @client_name "concerto_orchestrator"

  @impl true
  def run_session(spec, _config) do
    transcript_path = Path.join(spec.run_dir, "app-server-transcript.jsonl")
    File.write!(transcript_path, "")

    session = %{
      port: spec.handle.port,
      transcript_path: transcript_path,
      metadata: spec.metadata,
      paths: spec.paths,
      response_timeout_ms: spec.response_timeout_ms,
      timeout_at: System.monotonic_time(:millisecond) + spec.timeout_ms,
      next_id: 1,
      thread_id: nil,
      last_turn_id: nil,
      active_turn_id: nil,
      turn_count: 0,
      task_complete?: false,
      canceled?: false,
      interrupt_sent?: false,
      stop_reason: :turn_completed,
      status: :completed
    }

    with {:ok, session} <- initialize(session),
         {:ok, session} <- start_thread(session, spec.workspace_path),
         {:ok, session} <- run_turns(session, spec.prompt, spec.workspace_path, spec.work_item, spec.continue?) do
      {:ok,
       %{
         thread_id: session.thread_id,
         last_turn_id: session.last_turn_id,
         turn_count: session.turn_count,
         stop_reason: session.stop_reason,
         status: session.status
       }}
    end
  end

  defp initialize(session) do
    params = %{
      "clientInfo" => %{
        "name" => @client_name,
        "version" => Application.get_env(:concerto, :runtime_version, "0.1.0")
      }
    }

    with {:ok, session, _result} <- send_request(session, "initialize", params),
         {:ok, session} <- send_notification(session, "initialized", %{}) do
      {:ok, session}
    end
  end

  defp start_thread(session, workspace_path) do
    params = %{
      "cwd" => workspace_path,
      "approvalPolicy" => "never",
      "sandbox" => "workspace-write",
      "ephemeral" => true
    }

    with {:ok, session, %{"thread" => %{"id" => thread_id}}} <- send_request(session, "thread/start", params) do
      EventLogger.emit(session.paths, :session_started, Map.put(session.metadata, "thread_id", thread_id), %{})
      {:ok, %{session | thread_id: thread_id}}
    end
  end

  defp run_turns(session, initial_prompt, workspace_path, work_item, continue_fun) do
    Enum.reduce_while(1..Concerto.RuntimeConstants.turn_cap(), {:ok, session}, fn turn_number, {:ok, current} ->
      prompt =
        if turn_number == 1,
          do: initial_prompt,
          else: continuation_prompt(work_item.work_item_id)

      case start_turn(current, prompt, workspace_path, turn_number) do
        {:ok, next} when next.canceled? ->
          {:halt, {:ok, %{next | turn_count: turn_number, status: :canceled_by_reconciliation, stop_reason: :reconciliation}}}

        {:ok, next} ->
          next =
            if turn_number == Concerto.RuntimeConstants.turn_cap() do
              %{next | turn_count: turn_number, status: :completed, stop_reason: :turn_cap_reached}
            else
              %{next | turn_count: turn_number}
            end

          should_continue =
            turn_number < Concerto.RuntimeConstants.turn_cap() and
              next.status == :completed and
              not next.task_complete? and
              continue_fun.()

          if turn_number == Concerto.RuntimeConstants.turn_cap() or not should_continue do
            {:halt, {:ok, next}}
          else
            {:cont, {:ok, next}}
          end

        error ->
          {:halt, error}
      end
    end)
  end

  defp start_turn(session, prompt, workspace_path, turn_number) do
    params = %{
      "threadId" => session.thread_id,
      "cwd" => workspace_path,
      "approvalPolicy" => "never",
      "sandboxPolicy" => %{
        "type" => "externalSandbox",
        "networkAccess" => "enabled"
      },
      "input" => [%{"type" => "text", "text" => prompt}]
    }

    with {:ok, session, %{"turn" => %{"id" => turn_id}}} <- send_request(session, "turn/start", params) do
      EventLogger.emit(
        session.paths,
        :turn_started,
        Map.merge(session.metadata, %{"thread_id" => session.thread_id, "turn_id" => turn_id}),
        %{"turn_number" => turn_number}
      )

      await_turn_completion(%{session | active_turn_id: turn_id, last_turn_id: turn_id})
    end
  end

  defp await_turn_completion(session) do
    timeout_remaining = max(session.timeout_at - System.monotonic_time(:millisecond), 0)

    receive do
      {:concerto_cancel, :reconciliation, _state} ->
        interrupt_and_finish(%{session | canceled?: true}, :reconciliation)

      {port, {:data, data}} when port == session.port ->
        handle_turn_data(session, data)

      {port, {:exit_status, status}} when port == session.port ->
        {:error, {:app_server_exit, status}}
    after
      min(timeout_remaining, session.response_timeout_ms) ->
        if System.monotonic_time(:millisecond) >= session.timeout_at do
          interrupt_and_finish(%{session | stop_reason: :timeout, status: :failed}, :timeout)
        else
          await_turn_completion(session)
        end
    end
  end

  defp handle_server_request(session, %{"id" => id}, method)
       when method in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"] do
    send_response(session, id, %{"decision" => "decline"})
  end

  defp handle_server_request(session, %{"id" => id}, method)
       when method in ["item/tool/requestUserInput", "mcpServer/elicitation/request"] do
    send_error(session, id, -32_001, "unsupported unattended request: #{method}")
  end

  defp handle_server_request(session, %{"id" => id}, method) do
    send_error(session, id, -32_000, "unsupported request: #{method}")
  end

  defp interrupt_and_finish(session, reason) do
    if session.active_turn_id do
      session =
        if session.interrupt_sent? do
          session
        else
          write_payload(session, %{
            "id" => session.next_id,
            "method" => "turn/interrupt",
            "params" => %{"threadId" => session.thread_id, "turnId" => session.active_turn_id}
          }, "request")

          EventLogger.emit(
            session.paths,
            :turn_interrupted,
            Map.merge(session.metadata, %{"thread_id" => session.thread_id, "turn_id" => session.active_turn_id}),
            %{"reason" => Atom.to_string(reason)}
          )

          %{session | next_id: session.next_id + 1, interrupt_sent?: true}
        end

      await_turn_completion(%{session | canceled?: true, stop_reason: reason})
    else
      {:ok, %{session | canceled?: true, stop_reason: reason, status: :failed}}
    end
  end

  defp send_request(session, method, params) do
    id = session.next_id
    write_payload(session, %{"id" => id, "method" => method, "params" => params}, "request")
    await_response(%{session | next_id: id + 1}, id)
  end

  defp send_notification(session, method, params) do
    write_payload(session, %{"method" => method, "params" => params}, "notification")
    {:ok, session}
  end

  defp await_response(session, request_id) do
    receive do
      {port, {:data, data}} when port == session.port ->
        handle_response_data(session, request_id, data)

      {:concerto_cancel, :reconciliation, _state} ->
        interrupt_and_finish(%{session | canceled?: true}, :reconciliation)

      {port, {:exit_status, status}} when port == session.port ->
        {:error, {:app_server_exit, status}}
    after
      session.response_timeout_ms ->
        {:error, :response_timeout}
    end
  end

  defp send_response(session, id, result) do
    write_payload(session, %{"id" => id, "result" => result}, "response")
  end

  defp send_error(session, id, code, message) do
    write_payload(session, %{"id" => id, "error" => %{"code" => code, "message" => message}}, "response")
  end

  defp write_payload(session, payload, kind) do
    encoded = Jason.encode!(payload)
    write_transcript(session.transcript_path, "client_to_server", "stdin", encoded, kind)
    Port.command(session.port, [encoded, "\n"])
  end

  defp write_transcript(path, direction, stream, payload, kind \\ "notification") do
    row = %{
      "at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "direction" => direction,
      "stream" => stream,
      "kind" => kind,
      "payload" => payload
    }

    File.write!(path, [Jason.encode!(row), "\n"], [:append])
  end

  defp continuation_prompt(work_item_id) do
    [
      "Resume from the current workspace state instead of restarting from scratch.",
      "Treat the prior turn history as already present on the thread.",
      "Focus on the remaining work for the same work item.",
      "Do not ask for human input because the session is unattended.",
      "Work item: #{work_item_id}"
    ]
    |> Enum.join(" ")
  end

  defp status_from_turn("completed"), do: :completed
  defp status_from_turn("interrupted"), do: :canceled_by_reconciliation
  defp status_from_turn(_), do: :failed

  defp handle_turn_data(session, data) do
    line = normalize_port_data(data)
    write_transcript(session.transcript_path, "server_to_client", "stdout", line)

    case Jason.decode(line) do
      {:ok, %{"method" => "turn/completed", "params" => %{"turn" => turn}}} ->
        status = turn["status"]
        event = if status == "completed", do: :turn_completed, else: :turn_failed
        EventLogger.emit(session.paths, event, Map.merge(session.metadata, %{"thread_id" => session.thread_id, "turn_id" => session.active_turn_id}), %{})

        {:ok,
         %{session | active_turn_id: nil, canceled?: status == "interrupted" or session.canceled?, status: status_from_turn(status)}}

      {:ok, %{"method" => "codex/event/task_complete"}} ->
        await_turn_completion(%{session | task_complete?: true})

      {:ok, %{"id" => _id, "method" => method} = request} ->
        handle_server_request(session, request, method)
        await_turn_completion(session)

      {:ok, _message} ->
        await_turn_completion(session)

      {:error, _reason} ->
        write_transcript(session.transcript_path, "server_to_client", "stdout", line, "malformed")
        await_turn_completion(session)
    end
  end

  defp handle_response_data(session, request_id, data) do
    line = normalize_port_data(data)
    write_transcript(session.transcript_path, "server_to_client", "stdout", line)

    case Jason.decode(line) do
      {:ok, %{"id" => ^request_id, "result" => result}} ->
        {:ok, session, result}

      {:ok, %{"id" => ^request_id, "error" => error}} ->
        {:error, {:json_rpc_error, error}}

      {:ok, %{"id" => _id, "method" => method} = request} ->
        handle_server_request(session, request, method)
        await_response(session, request_id)

      {:ok, _message} ->
        await_response(session, request_id)

      {:error, _reason} ->
        write_transcript(session.transcript_path, "server_to_client", "stdout", line, "malformed")
        await_response(session, request_id)
    end
  end

  defp normalize_port_data({:eol, line}), do: line
  defp normalize_port_data({:noeol, line}), do: line
  defp normalize_port_data(line), do: line
end
