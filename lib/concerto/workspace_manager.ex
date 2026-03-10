defmodule Concerto.WorkspaceManager do
  @moduledoc false

  alias Concerto.Workspace

  def ensure_workspace(workspace_root, workspace_key) do
    path = Path.join(workspace_root, workspace_key)

    created_now =
      case File.stat(path) do
        {:ok, _} ->
          false

        {:error, :enoent} ->
          File.mkdir_p!(path)
          true
      end

    {:ok, %Workspace{workspace_key: workspace_key, path: path, created_now: created_now, materialized_now: false}}
  end
end
