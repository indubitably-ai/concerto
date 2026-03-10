defmodule Mix.Tasks.Concerto.Run do
  @moduledoc false
  @shortdoc "Runs the Concerto orchestrator against a workflow root"

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [workflow_root: :string])

    workflow_root =
      opts[:workflow_root] ||
        raise Mix.Error, "expected --workflow-root /abs/path"

    Application.put_env(:concerto, :workflow_root, Path.expand(workflow_root))
    Application.ensure_all_started(:concerto)
    Process.sleep(:infinity)
  end
end
