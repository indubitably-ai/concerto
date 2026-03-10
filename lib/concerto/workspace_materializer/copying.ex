defmodule Concerto.WorkspaceMaterializer.Copying do
  @moduledoc false

  @behaviour Concerto.WorkspaceMaterializer

  alias Concerto.WorkspaceMaterialization

  @marker ".concerto-materialized.json"
  @excluded_names MapSet.new([".concerto", "evidence", ".git", "_build", "deps", "node_modules"])

  @impl true
  def materialize(workflow_root, workspace_key, workspace_path, _paths, _options) do
    marker_path = Path.join(workspace_path, @marker)

    with :ok <- File.mkdir_p(workspace_path),
         :ok <- copy_tree(workflow_root, workspace_path, workspace_path) do
      materialized_now =
        case File.exists?(marker_path) do
          true ->
            false

          false ->
            payload = %{
              "materialized_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "workflow_root" => Path.expand(workflow_root)
            }

            File.write!(marker_path, Jason.encode_to_iodata!(payload, pretty: true))
            true
        end

      {:ok,
       %WorkspaceMaterialization{
         workspace_key: workspace_key,
         workspace_path: workspace_path,
         materialized_now: materialized_now,
         ready: true
       }}
    end
  end

  defp copy_tree(source_root, dest_root, workspace_path) do
    source_root
    |> File.ls!()
    |> Enum.reject(&excluded?(&1, source_root, workspace_path))
    |> Enum.each(fn entry ->
      source = Path.join(source_root, entry)
      target = Path.join(dest_root, entry)

      cond do
        File.dir?(source) ->
          File.mkdir_p!(target)
          copy_tree(source, target, workspace_path)

        File.regular?(source) ->
          File.cp(source, target)

        true ->
          :ok
      end
    end)

    :ok
  end

  defp excluded?(entry, source_root, workspace_path) do
    path = Path.expand(Path.join(source_root, entry))

    MapSet.member?(@excluded_names, entry) or path == Path.expand(workspace_path) or
      String.starts_with?(Path.expand(workspace_path), path <> "/")
  end
end
