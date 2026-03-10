defmodule Concerto.TestSupport.Evidence do
  @moduledoc false

  def start!(scenario_id, layer, opts \\ []) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    dir = Path.join(["evidence", scenario_id, timestamp])
    File.mkdir_p!(dir)

    bundle = %{
      scenario_id: scenario_id,
      layer: layer,
      command: Keyword.get(opts, :command, infer_command(layer)),
      started_at: DateTime.utc_now(),
      dir: dir,
      artifacts: %{}
    }

    bundle
    |> write_artifact("test_output", "test-output.txt", "")
    |> write_artifact("structured_log", "structured.log", "")
    |> maybe_init_codex_artifacts(opts)
  end

  def log(bundle, line) do
    File.write!(artifact_path(bundle, "test_output"), ["#{line}\n"], [:append])
    bundle
  end

  def write_artifact(bundle, logical_name, filename, contents) do
    path = Path.join(bundle.dir, filename)
    File.write!(path, contents)
    put_in(bundle.artifacts[logical_name], filename)
  end

  def copy_artifact(bundle, logical_name, source_path, filename \\ nil) do
    target_name = filename || Path.basename(source_path)
    target_path = Path.join(bundle.dir, target_name)
    File.cp!(source_path, target_path)
    put_in(bundle.artifacts[logical_name], target_name)
  end

  def finish!(bundle, exit_status, opts \\ []) do
    manifest = %{
      "scenario_id" => bundle.scenario_id,
      "layer" => bundle.layer,
      "command" => bundle.command,
      "exit_status" => exit_status,
      "started_at" => DateTime.to_iso8601(bundle.started_at),
      "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "redacted_env" => redacted_env(),
      "artifacts" => bundle.artifacts
    }
    |> maybe_put("notes", opts[:notes])

    File.write!(Path.join(bundle.dir, "manifest.json"), [Jason.encode!(manifest, pretty: true), "\n"])
  end

  def artifact_path(bundle, logical_name) do
    filename = Map.fetch!(bundle.artifacts, logical_name)
    Path.join(bundle.dir, filename)
  end

  defp maybe_init_codex_artifacts(bundle, opts) do
    if Keyword.get(opts, :starts_codex, false) do
      bundle
      |> write_artifact("app_server_transcript", "app-server-transcript.jsonl", "")
      |> write_artifact("stderr", "stderr.txt", "")
    else
      bundle
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp infer_command("Unit"), do: "mix test test/unit"
  defp infer_command("Component"), do: "mix test test/component"
  defp infer_command("Integration"), do: "mix test test/integration"
  defp infer_command("Smoke"), do: "mix test test/smoke"

  defp redacted_env do
    System.get_env()
    |> Enum.filter(fn {key, _value} -> String.contains?(key, ["KEY", "TOKEN", "SECRET"]) end)
    |> Map.new(fn {key, value} -> {key, redact_value(value)} end)
  end

  defp redact_value(value) when byte_size(value) <= 8, do: String.duplicate("*", byte_size(value))

  defp redact_value(value) do
    prefix = binary_part(value, 0, 4)
    suffix = binary_part(value, byte_size(value) - 4, 4)
    "#{prefix}...#{suffix}"
  end
end
