defmodule Concerto.Integration.AppServerIntegrationTest do
  use ExUnit.Case, async: false

  alias Concerto.AppServerClient.Stdio
  alias Concerto.TestSupport.{DirectProcessRuntime, Evidence, Temp}

  @script Path.expand("test/fixtures/fake_app_server.py", File.cwd!())

  test "ACC-10 minimal handshake and one-turn run works over stdio" do
    bundle = Evidence.start!("ACC-10", "Integration", starts_codex: true)
    run_dir = Temp.tmp_dir!("acc-10-run")
    workspace_path = Temp.tmp_dir!("acc-10-workspace")

    {:ok, handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "acc10", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "complete"}
      )

    {:ok, result} =
      Stdio.run_session(
        %{
          handle: handle,
          metadata: %{
            "work_item_id" => "wi-1",
            "workspace_key" => "repo-a",
            "dispatch_revision" => "rev-1",
            "trace_id" => "trace",
            "span_id" => "span"
          },
          prompt: "hello",
          workspace_path: workspace_path,
          run_dir: run_dir,
          paths: %{runs_root: run_dir},
          work_item: %{work_item_id: "wi-1"},
          continue?: fn -> false end,
          timeout_ms: 5_000,
          response_timeout_ms: 1_000
        },
        %{}
      )

    assert result.thread_id == "thr_fixture"
    transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert transcript =~ "initialize"
    assert transcript =~ "thread/start"
    assert transcript =~ "turn/start"
    assert transcript =~ "externalSandbox"

    bundle =
      Evidence.copy_artifact(
        bundle,
        "app_server_transcript",
        Path.join(run_dir, "app-server-transcript.jsonl")
      )

    bundle = Evidence.copy_artifact(bundle, "stderr", Path.join(run_dir, "stderr.txt"))
    Evidence.finish!(bundle, 0)
  end

  test "ACC-11 interrupt path sends turn/interrupt when reconciliation cancels an active turn" do
    bundle = Evidence.start!("ACC-11", "Integration", starts_codex: true)
    run_dir = Temp.tmp_dir!("acc-11-run")
    workspace_path = Temp.tmp_dir!("acc-11-workspace")

    {:ok, handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "acc11", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "interrupt"}
      )

    assert {:ok, %{stop_reason: :reconciliation, status: :canceled_by_reconciliation}} =
             Stdio.run_session(
               %{
                 handle: handle,
                 metadata: %{
                   "work_item_id" => "wi-1",
                   "workspace_key" => "repo-a",
                   "dispatch_revision" => "rev-1",
                   "trace_id" => "trace",
                   "span_id" => "span"
                 },
                 prompt: "hello",
                 workspace_path: workspace_path,
                 run_dir: run_dir,
                 paths: %{runs_root: run_dir},
                 work_item: %{work_item_id: "wi-1"},
                 continue?: fn -> false end,
                 timeout_ms: 250,
                 response_timeout_ms: 100
               },
               %{}
             )

    transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert transcript =~ "turn/interrupt"

    bundle =
      Evidence.copy_artifact(
        bundle,
        "app_server_transcript",
        Path.join(run_dir, "app-server-transcript.jsonl")
      )

    bundle = Evidence.copy_artifact(bundle, "stderr", Path.join(run_dir, "stderr.txt"))
    Evidence.finish!(bundle, 0)
  end

  test "ACC-16 continuation turns reuse the same thread and stop at five turns" do
    bundle = Evidence.start!("ACC-16", "Integration", starts_codex: true)
    run_dir = Temp.tmp_dir!("acc-16-run")
    workspace_path = Temp.tmp_dir!("acc-16-workspace")

    {:ok, handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "acc16", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "complete"}
      )

    {:ok, result} =
      Stdio.run_session(
        %{
          handle: handle,
          metadata: %{
            "work_item_id" => "wi-1",
            "workspace_key" => "repo-a",
            "dispatch_revision" => "rev-1",
            "trace_id" => "trace",
            "span_id" => "span"
          },
          prompt: "hello",
          workspace_path: workspace_path,
          run_dir: run_dir,
          paths: %{runs_root: run_dir},
          work_item: %{work_item_id: "wi-1"},
          continue?: fn -> true end,
          timeout_ms: 5_000,
          response_timeout_ms: 1_000
        },
        %{}
      )

    transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert result.turn_count == 5
    assert transcript =~ "thr_fixture"

    turn_requests =
      transcript
      |> String.split("\n", trim: true)
      |> Enum.count(fn line ->
        decoded = Jason.decode!(line)

        decoded["direction"] == "client_to_server" and
          String.contains?(decoded["payload"], "\"method\":\"turn/start\"")
      end)

    assert turn_requests == 5

    bundle =
      Evidence.copy_artifact(
        bundle,
        "app_server_transcript",
        Path.join(run_dir, "app-server-transcript.jsonl")
      )

    bundle = Evidence.copy_artifact(bundle, "stderr", Path.join(run_dir, "stderr.txt"))
    Evidence.finish!(bundle, 0)
  end

  test "task_complete notification stops continuation even when lifecycle still allows it" do
    run_dir = Temp.tmp_dir!("task-complete-run")
    workspace_path = Temp.tmp_dir!("task-complete-workspace")

    {:ok, handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "taskcomplete", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "task_complete"}
      )

    {:ok, result} =
      Stdio.run_session(
        %{
          handle: handle,
          metadata: %{
            "work_item_id" => "wi-1",
            "workspace_key" => "repo-a",
            "dispatch_revision" => "rev-1",
            "trace_id" => "trace",
            "span_id" => "span"
          },
          prompt: "hello",
          workspace_path: workspace_path,
          run_dir: run_dir,
          paths: %{runs_root: run_dir},
          work_item: %{work_item_id: "wi-1"},
          continue?: fn -> true end,
          timeout_ms: 5_000,
          response_timeout_ms: 1_000
        },
        %{}
      )

    transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert result.turn_count == 1
    assert transcript =~ "codex/event/task_complete"
  end

  test "ACC-17 approval and user-input requests are resolved deterministically" do
    bundle = Evidence.start!("ACC-17", "Integration", starts_codex: true)
    run_dir = Temp.tmp_dir!("acc-17-run")
    workspace_path = Temp.tmp_dir!("acc-17-workspace")

    {:ok, approval_handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "acc17a", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "approval"}
      )

    {:ok, _approval_result} =
      Stdio.run_session(
        %{
          handle: approval_handle,
          metadata: %{
            "work_item_id" => "wi-1",
            "workspace_key" => "repo-a",
            "dispatch_revision" => "rev-1",
            "trace_id" => "trace",
            "span_id" => "span"
          },
          prompt: "hello",
          workspace_path: workspace_path,
          run_dir: run_dir,
          paths: %{runs_root: run_dir},
          work_item: %{work_item_id: "wi-1"},
          continue?: fn -> false end,
          timeout_ms: 5_000,
          response_timeout_ms: 1_000
        },
        %{}
      )

    approval_transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert approval_transcript =~ "decline"

    run_dir = Temp.tmp_dir!("acc-17b-run")
    workspace_path = Temp.tmp_dir!("acc-17b-workspace")

    {:ok, input_handle} =
      DirectProcessRuntime.start_app_server(
        %{run_id: "acc17b", run_dir: run_dir, workspace_path: workspace_path},
        %{script: @script, mode: "user_input"}
      )

    assert {:ok, %{status: :failed}} =
             Stdio.run_session(
               %{
                 handle: input_handle,
                 metadata: %{
                   "work_item_id" => "wi-1",
                   "workspace_key" => "repo-a",
                   "dispatch_revision" => "rev-1",
                   "trace_id" => "trace",
                   "span_id" => "span"
                 },
                 prompt: "hello",
                 workspace_path: workspace_path,
                 run_dir: run_dir,
                 paths: %{runs_root: run_dir},
                 work_item: %{work_item_id: "wi-1"},
                 continue?: fn -> false end,
                 timeout_ms: 5_000,
                 response_timeout_ms: 1_000
               },
               %{}
             )

    input_transcript = File.read!(Path.join(run_dir, "app-server-transcript.jsonl"))
    assert input_transcript =~ "unsupported unattended request"

    bundle =
      Evidence.copy_artifact(
        bundle,
        "app_server_transcript",
        Path.join(run_dir, "app-server-transcript.jsonl")
      )

    bundle = Evidence.copy_artifact(bundle, "stderr", Path.join(run_dir, "stderr.txt"))
    Evidence.finish!(bundle, 0)
  end
end
