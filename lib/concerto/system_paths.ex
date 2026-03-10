defmodule Concerto.SystemPaths do
  @moduledoc false

  def build(workflow_root) do
    workflow_root = Path.expand(workflow_root)
    state_root = Path.join(workflow_root, ".concerto/state")

    %{
      workflow_root: workflow_root,
      workflow_path: Path.join(workflow_root, "WORKFLOW.md"),
      concerto_root: Path.join(workflow_root, ".concerto"),
      state_root: state_root,
      revisions_root: Path.join(state_root, "revisions"),
      ownership_root: Path.join(state_root, "ownership"),
      run_state_root: Path.join(state_root, "runs"),
      runs_root: Path.join(workflow_root, ".concerto/runs")
    }
  end

  def ensure!(paths) do
    paths
    |> Map.take([:concerto_root, :state_root, :revisions_root, :ownership_root, :run_state_root, :runs_root])
    |> Map.values()
    |> Enum.each(&File.mkdir_p!/1)
  end
end
