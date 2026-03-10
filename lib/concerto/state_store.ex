defmodule Concerto.StateStore do
  @moduledoc false

  alias Concerto.RunAttempt

  def last_terminal_revision(paths, work_item_id) do
    paths
    |> revision_path(work_item_id)
    |> File.read()
    |> case do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"dispatch_revision" => revision}} -> {:ok, revision}
          _ -> {:error, :invalid_revision_state}
        end

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put_terminal_revision(paths, work_item_id, dispatch_revision) do
    payload = %{
      "work_item_id" => work_item_id,
      "dispatch_revision" => dispatch_revision,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    write_json(revision_path(paths, work_item_id), payload)
  end

  def persist_run_attempt(paths, %RunAttempt{} = attempt) do
    payload = %{
      "run_id" => attempt.run_id,
      "work_item_id" => attempt.work_item_id,
      "workspace_key" => attempt.workspace_key,
      "dispatch_revision" => attempt.dispatch_revision,
      "workspace_path" => attempt.workspace_path,
      "thread_id" => attempt.thread_id,
      "last_turn_id" => attempt.last_turn_id,
      "turn_count" => attempt.turn_count,
      "trace" => Map.from_struct(attempt.trace),
      "started_at" => DateTime.to_iso8601(attempt.started_at),
      "finished_at" => attempt.finished_at && DateTime.to_iso8601(attempt.finished_at),
      "stop_reason" => Atom.to_string(attempt.stop_reason),
      "status" => Atom.to_string(attempt.status)
    }

    write_json(Path.join(paths.run_state_root, "#{attempt.run_id}.json"), payload)
  end

  def write_ownership_manifest(paths, run_id, manifest) do
    write_json(Path.join(paths.ownership_root, "#{run_id}.json"), manifest)
  end

  def delete_ownership_manifest(paths, run_id) do
    Path.join(paths.ownership_root, "#{run_id}.json") |> File.rm()
  end

  def list_ownership_manifests(paths) do
    with {:ok, entries} <- File.ls(paths.ownership_root) do
      entries
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&Path.join(paths.ownership_root, &1))
      |> Enum.map(&read_json_file/1)
      |> Enum.reject(&match?({:error, _}, &1))
      |> Enum.map(fn {:ok, manifest} -> manifest end)
      |> then(&{:ok, &1})
    end
  end

  defp revision_path(paths, work_item_id) do
    Path.join(paths.revisions_root, encoded_name(work_item_id) <> ".json")
  end

  defp encoded_name(value), do: Base.url_encode64(value, padding: false)

  defp read_json_file(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, json} <- Jason.decode(contents) do
      {:ok, Map.put(json, "__path__", path)}
    end
  end

  defp write_json(path, payload) do
    path |> Path.dirname() |> File.mkdir_p!()
    encoded = Jason.encode_to_iodata!(payload, pretty: true)
    File.write(path, [encoded, "\n"])
  end
end
