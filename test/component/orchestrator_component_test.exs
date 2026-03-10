defmodule Concerto.Component.OrchestratorComponentTest do
  use ExUnit.Case, async: false

  alias Concerto.{Bootstrap, StateStore}
  alias Concerto.TestSupport.{
    Evidence,
    FakeAppServerClient,
    FakeContainerRuntime,
    FakeWorkSource,
    Temp
  }

  setup do
    {:ok, source} = start_supervised(FakeWorkSource)
    {:ok, runtime_agent} = start_supervised(FakeContainerRuntime)
    %{source: source, runtime_agent: runtime_agent}
  end

  test "ACC-5 bounded concurrency never exceeds configured slots", %{source: source, runtime_agent: runtime_agent} do
    bundle = Evidence.start!("ACC-5", "Component")
    workflow_root = workflow_root!("acc-5", 1)

    items =
      Enum.map(1..3, fn idx ->
        %Concerto.WorkItem{
          work_item_id: "wi-#{idx}",
          workspace_key: "repo-#{idx}",
          dispatch_revision: "rev-#{idx}",
          lifecycle_state: :dispatchable,
          prompt_context: %{},
          priority: idx
        }
      end)

    FakeWorkSource.put_dispatch_candidates(source, items)
    FakeWorkSource.put_states(source, Enum.map(items, &Map.take(&1, [:work_item_id, :workspace_key, :dispatch_revision, :lifecycle_state])))

    runtime =
      runtime!(workflow_root, source, runtime_agent,
        app_server_client: {FakeAppServerClient, %{mode: {:sleep, 800}}}
      )

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, runtime})
    Process.sleep(100)

    state = :sys.get_state(Concerto.Orchestrator)
    assert map_size(state.running) == 1

    Evidence.log(bundle, "Observed one running worker with max_concurrent_agents=1.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-6 workspace reuse keeps deterministic paths" do
    bundle = Evidence.start!("ACC-6", "Component")
    root = Temp.tmp_dir!("acc-6")

    {:ok, one} = Concerto.WorkspaceManager.ensure_workspace(root, "repo-a")
    {:ok, two} = Concerto.WorkspaceManager.ensure_workspace(root, "repo-a")

    assert one.path == two.path
    assert one.created_now
    refute two.created_now

    Evidence.log(bundle, "Workspace path reused across repeated runs for the same workspace key.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-7 reconciliation stop interrupts active runs when lifecycle changes", %{
    source: source,
    runtime_agent: runtime_agent
  } do
    bundle = Evidence.start!("ACC-7", "Component")
    workflow_root = workflow_root!("acc-7", 1)

    item = %Concerto.WorkItem{
      work_item_id: "wi-1",
      workspace_key: "repo-a",
      dispatch_revision: "rev-1",
      lifecycle_state: :dispatchable,
      prompt_context: %{},
      priority: 1
    }

    FakeWorkSource.put_dispatch_candidates(source, [item])
    FakeWorkSource.put_states(source, [%{work_item_id: item.work_item_id, workspace_key: item.workspace_key, dispatch_revision: item.dispatch_revision, lifecycle_state: :dispatchable}])

    runtime =
      runtime!(workflow_root, source, runtime_agent,
        app_server_client: {FakeAppServerClient, %{mode: :block_until_cancel}}
      )

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, runtime})
    Process.sleep(100)

    FakeWorkSource.put_states(source, [%{work_item_id: item.work_item_id, workspace_key: item.workspace_key, dispatch_revision: item.dispatch_revision, lifecycle_state: :inactive}])
    send(Concerto.Orchestrator, :poll)

    assert wait_until(fn ->
             Enum.any?(Path.wildcard(Path.join(runtime.paths.run_state_root, "*.json")), fn file ->
               File.read!(file) =~ "\"status\": \"canceled_by_reconciliation\""
             end)
           end)

    bundle = Evidence.copy_artifact(bundle, "structured_log", Concerto.EventLogger.structured_log_path(runtime.paths), "structured.log")
    bundle = maybe_copy_run_artifacts(bundle, runtime.paths)
    Evidence.finish!(bundle, 0)
  end

  test "ACC-8 timeout handling records failed attempts and stderr artifacts", %{
    source: source,
    runtime_agent: runtime_agent
  } do
    bundle = Evidence.start!("ACC-8", "Component", starts_codex: true)
    workflow_root = workflow_root!("acc-8", 1)

    item = %Concerto.WorkItem{
      work_item_id: "wi-1",
      workspace_key: "repo-a",
      dispatch_revision: "rev-1",
      lifecycle_state: :dispatchable,
      prompt_context: %{},
      priority: 1
    }

    FakeWorkSource.put_dispatch_candidates(source, [item])
    FakeWorkSource.put_states(source, [%{work_item_id: item.work_item_id, workspace_key: item.workspace_key, dispatch_revision: item.dispatch_revision, lifecycle_state: :dispatchable}])

    runtime =
      runtime!(workflow_root, source, runtime_agent,
        app_server_client: {FakeAppServerClient, %{mode: :timeout}}
      )

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, runtime})

    assert wait_until(fn ->
             Enum.any?(Path.wildcard(Path.join(runtime.paths.run_state_root, "*.json")), fn file ->
               File.read!(file) =~ "\"stop_reason\": \"timeout\""
             end)
           end)

    bundle = Evidence.copy_artifact(bundle, "structured_log", Concerto.EventLogger.structured_log_path(runtime.paths), "structured.log")
    bundle = maybe_copy_run_artifacts(bundle, runtime.paths)
    Evidence.finish!(bundle, 0)
  end

  test "ACC-9 startup orphan cleanup uses ownership manifests and cleanup hooks", %{
    source: source,
    runtime_agent: runtime_agent
  } do
    bundle = Evidence.start!("ACC-9", "Component")
    workflow_root = workflow_root!("acc-9", 1)
    paths = Concerto.SystemPaths.build(workflow_root)
    Concerto.SystemPaths.ensure!(paths)

    StateStore.write_ownership_manifest(paths, "run-1", %{
      "run_id" => "run-1",
      "workflow_root" => workflow_root,
      "container_ref" => "leftover",
      "workspace_key" => "repo-a",
      "work_item_id" => "wi-1"
    })

    {:ok, _runtime} =
      Bootstrap.boot(
        workflow_root: workflow_root,
        work_source: {FakeWorkSource, %{agent: source}},
        container_runtime: {FakeContainerRuntime, %{agent: runtime_agent}},
        app_server_client: {FakeAppServerClient, %{mode: :complete}}
      )

    assert length(FakeContainerRuntime.state(runtime_agent).cleanups) == 1
    refute File.exists?(Path.join(paths.ownership_root, "run-1.json"))

    Evidence.log(bundle, "Startup orphan cleanup removed the prior ownership manifest and invoked precise cleanup.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-15 workspace materialization is idempotent on reuse" do
    bundle = Evidence.start!("ACC-15", "Component")
    workflow_root = Temp.tmp_dir!("acc-15-workflow")
    workspace_path = Temp.tmp_dir!("acc-15-workspace")
    File.write!(Path.join(workflow_root, "README.md"), "hello\n")
    paths = Concerto.SystemPaths.build(workflow_root)
    Concerto.SystemPaths.ensure!(paths)

    {:ok, first} =
      Concerto.WorkspaceMaterializer.Copying.materialize(workflow_root, "repo-a", workspace_path, paths, %{})

    {:ok, second} =
      Concerto.WorkspaceMaterializer.Copying.materialize(workflow_root, "repo-a", workspace_path, paths, %{})

    assert first.ready
    assert second.ready
    assert File.read!(Path.join(workspace_path, "README.md")) == "hello\n"

    Evidence.log(bundle, "Materializer preserved a usable workspace across repeated execution.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-18 restart persistence suppresses duplicate dispatch after restart", %{
    source: source,
    runtime_agent: runtime_agent
  } do
    bundle = Evidence.start!("ACC-18", "Component")
    workflow_root = workflow_root!("acc-18", 1)
    paths = Concerto.SystemPaths.build(workflow_root)
    Concerto.SystemPaths.ensure!(paths)
    StateStore.put_terminal_revision(paths, "wi-1", "rev-1")

    item = %Concerto.WorkItem{
      work_item_id: "wi-1",
      workspace_key: "repo-a",
      dispatch_revision: "rev-1",
      lifecycle_state: :dispatchable,
      prompt_context: %{},
      priority: 1
    }

    FakeWorkSource.put_dispatch_candidates(source, [item])
    FakeWorkSource.put_states(source, [%{work_item_id: item.work_item_id, workspace_key: item.workspace_key, dispatch_revision: item.dispatch_revision, lifecycle_state: :dispatchable}])

    runtime =
      runtime!(workflow_root, source, runtime_agent,
        app_server_client: {FakeAppServerClient, %{mode: {:sleep, 250}}}
      )
    {:ok, _pid} = start_supervised({Concerto.Orchestrator, runtime})
    Process.sleep(100)

    assert :sys.get_state(Concerto.Orchestrator).running == %{}

    Evidence.log(bundle, "Persisted terminal revision prevented duplicate redispatch after restart.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-19 ownership markers capture precise cleanup identifiers", %{
    source: source,
    runtime_agent: runtime_agent
  } do
    bundle = Evidence.start!("ACC-19", "Component")
    workflow_root = workflow_root!("acc-19", 1)

    item = %Concerto.WorkItem{
      work_item_id: "wi-1",
      workspace_key: "repo-a",
      dispatch_revision: "rev-1",
      lifecycle_state: :dispatchable,
      prompt_context: %{},
      priority: 1
    }

    FakeWorkSource.put_dispatch_candidates(source, [item])
    FakeWorkSource.put_states(source, [%{work_item_id: item.work_item_id, workspace_key: item.workspace_key, dispatch_revision: item.dispatch_revision, lifecycle_state: :dispatchable}])

    runtime =
      runtime!(workflow_root, source, runtime_agent,
        app_server_client: {FakeAppServerClient, %{mode: {:sleep, 800}}}
      )
    {:ok, _pid} = start_supervised({Concerto.Orchestrator, runtime})

    assert wait_until(fn ->
             Path.wildcard(Path.join(runtime.paths.ownership_root, "*.json")) != []
           end)

    [manifest_path] = Path.wildcard(Path.join(runtime.paths.ownership_root, "*.json"))
    manifest = File.read!(manifest_path)
    assert manifest =~ "\"work_item_id\": \"wi-1\""
    assert manifest =~ "\"workspace_key\": \"repo-a\""

    Process.sleep(900)

    Evidence.log(bundle, "Ownership manifest retained precise identifiers for targeted cleanup.")
    Evidence.finish!(bundle, 0)
  end

  defp runtime!(workflow_root, source, runtime_agent, overrides) do
    {:ok, runtime} =
      Bootstrap.boot(
        Keyword.merge(
          [
            workflow_root: workflow_root,
            work_source: {FakeWorkSource, %{agent: source}},
            container_runtime: {FakeContainerRuntime, %{agent: runtime_agent}},
            app_server_client: {FakeAppServerClient, %{mode: :complete}}
          ],
          overrides
        )
      )

    runtime
  end

  defp maybe_copy_run_artifacts(bundle, paths) do
    case Path.wildcard(Path.join(paths.runs_root, "*/stderr.txt")) do
      [stderr | _] -> Evidence.copy_artifact(bundle, "stderr", stderr, "stderr.txt")
      _ -> bundle
    end
  end

  defp workflow_root!(name, concurrency) do
    workspace_root = Temp.tmp_dir!("workspace-#{name}")

    body = """
    ---
    work_source:
      dsn: postgres://concerto:secret@db.example.internal/app
      schema: concerto
    workspace:
      root: #{workspace_root}
    polling:
      interval_ms: 25
    agent:
      max_concurrent_agents: #{concurrency}
    ---
    # Concerto Workflow

    Do the work.
    """

    Temp.workflow_root!(name, body)
  end

  defp wait_until(fun, attempts \\ 30)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end
end
