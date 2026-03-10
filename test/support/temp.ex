defmodule Concerto.TestSupport.Temp do
  @moduledoc false

  def tmp_dir!(name) do
    path =
      Path.join(System.tmp_dir!(), "concerto-tests/#{name}-#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  def workflow_root!(name, body \\ default_body()) do
    root = tmp_dir!(name)
    File.write!(Path.join(root, "WORKFLOW.md"), body)
    root
  end

  def default_body do
    """
    ---
    work_source:
      dsn: postgres://concerto:secret@db.example.internal/app
      schema: concerto
    workspace:
      root: /tmp/concerto-workspaces
    polling:
      interval_ms: 25
    agent:
      max_concurrent_agents: 1
    ---
    # Concerto Workflow

    Do the work.
    """
  end
end
