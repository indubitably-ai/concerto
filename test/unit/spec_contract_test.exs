defmodule Concerto.Unit.SpecContractTest do
  use ExUnit.Case, async: false

  alias Concerto.{DispatchPolicy, EventLogger, StateStore, TraceContext, WorkItem, WorkflowLoader}
  alias Concerto.TestSupport.{Evidence, Temp}

  test "ACC-1 workflow parsing and startup validation" do
    bundle = Evidence.start!("ACC-1", "Unit")
    missing_root = Temp.tmp_dir!("missing-workflow")
    invalid_root = Temp.tmp_dir!("invalid-workflow")
    File.write!(Path.join(invalid_root, "WORKFLOW.md"), "not-valid")

    assert {:error, _} = WorkflowLoader.load(missing_root)
    assert {:error, _} = WorkflowLoader.load(invalid_root)

    Evidence.log(bundle, "Validated missing and invalid WORKFLOW failure.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-2 workflow prompt assembly keeps workflow root distinct from workspace root" do
    bundle = Evidence.start!("ACC-2", "Unit")
    workflow_root = workflow_root!("acc-2")
    {:ok, workflow} = WorkflowLoader.load(workflow_root)

    assert workflow.workflow_root != workflow.config.workspace.root

    {:ok, work_item} =
      WorkItem.normalize(%{
        "work_item_id" => "wi-1",
        "workspace_key" => "repo-a",
        "dispatch_revision" => "rev-1",
        "lifecycle_state" => "dispatchable",
        "prompt_context" => %{"ticket" => 1},
        "priority" => 1
      })

    prompt = WorkflowLoader.assemble_prompt(workflow.body, work_item)

    assert prompt =~ "# Concerto Workflow"
    assert prompt =~ "## Work Item"
    assert prompt =~ "\"dispatch_revision\":\"rev-1\""

    Evidence.log(bundle, "Prompt assembly includes workflow body and normalized work item JSON.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-3 candidate ordering sorts by priority then work_item_id" do
    bundle = Evidence.start!("ACC-3", "Unit")

    candidates =
      [
        %WorkItem{work_item_id: "b", workspace_key: "b", dispatch_revision: "1", lifecycle_state: :dispatchable, prompt_context: %{}, priority: nil},
        %WorkItem{work_item_id: "c", workspace_key: "c", dispatch_revision: "1", lifecycle_state: :dispatchable, prompt_context: %{}, priority: 2},
        %WorkItem{work_item_id: "a", workspace_key: "a", dispatch_revision: "1", lifecycle_state: :dispatchable, prompt_context: %{}, priority: 1}
      ]

    assert Enum.map(DispatchPolicy.sort_candidates(candidates), & &1.work_item_id) == ["a", "c", "b"]

    Evidence.log(bundle, "Candidate ordering matches priority asc, work_item_id asc with null priority last.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-4 dispatch_revision dedupe suppresses unchanged terminal revisions" do
    bundle = Evidence.start!("ACC-4", "Unit")
    root = Temp.tmp_dir!("acc-4")
    paths = Concerto.SystemPaths.build(root)
    Concerto.SystemPaths.ensure!(paths)
    :ok = StateStore.put_terminal_revision(paths, "wi-1", "rev-1")

    candidate =
      %WorkItem{
        work_item_id: "wi-1",
        workspace_key: "repo-a",
        dispatch_revision: "rev-1",
        lifecycle_state: :dispatchable,
        prompt_context: %{},
        priority: 1
      }

    changed = %{candidate | dispatch_revision: "rev-2"}

    assert DispatchPolicy.eligible_candidates([candidate], %{}, paths) == []
    assert DispatchPolicy.eligible_candidates([changed], %{}, paths) == [changed]

    Evidence.log(bundle, "Unchanged revisions are deduped while changed revisions remain eligible.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-20 runtime event and trace contract emits validated events and violations" do
    bundle = Evidence.start!("ACC-20", "Unit")
    root = Temp.tmp_dir!("acc-20")
    paths = Concerto.SystemPaths.build(root)
    Concerto.SystemPaths.ensure!(paths)
    trace = TraceContext.root()

    EventLogger.emit(paths, :dispatch_started, %{"trace_id" => trace.trace_id, "span_id" => trace.span_id}, %{})
    EventLogger.emit(paths, :not_a_real_event, %{}, %{})

    structured_log = File.read!(EventLogger.structured_log_path(paths))
    assert structured_log =~ "dispatch_started"
    assert structured_log =~ "event_contract_violation"

    bundle = Evidence.copy_artifact(bundle, "structured_log", EventLogger.structured_log_path(paths), "structured.log")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-21 evidence bundle retention redacts secrets" do
    bundle = Evidence.start!("ACC-21", "Unit")
    System.put_env("TEST_SECRET_TOKEN", "abcd1234wxyz")
    Evidence.log(bundle, "Evidence helper wrote manifest with redacted env values.")
    Evidence.finish!(bundle, 0)

    manifest = Path.join(bundle.dir, "manifest.json") |> File.read!() |> Jason.decode!()
    assert get_in(manifest, ["redacted_env", "TEST_SECRET_TOKEN"]) == "abcd...wxyz"
  after
    System.delete_env("TEST_SECRET_TOKEN")
  end

  defp workflow_root!(name) do
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
      max_concurrent_agents: 1
    ---
    # Concerto Workflow

    Do the work.
    """

    Temp.workflow_root!(name, body)
  end
end
