defmodule Concerto.TestSupport.DirectProcessRuntime do
  @moduledoc false

  @behaviour Concerto.ContainerRuntime

  @impl true
  def start_app_server(spec, config) do
    script = Map.fetch!(config, :script)
    mode = Map.get(config, :mode, "complete")
    stderr_path = Path.join(spec.run_dir, "stderr.txt")
    File.write!(stderr_path, "")
    shell = System.find_executable("sh") || "/bin/sh"

    port =
      Port.open({:spawn_executable, shell}, [
        :binary,
        :exit_status,
        {:line, 1_048_576},
        {:env, [{~c"FAKE_CODEX_MODE", String.to_charlist(mode)}, {~c"FAKE_CODEX_STDERR", String.to_charlist(stderr_path)}]},
        {:args, ["-lc", "python3 #{script} 2>>#{stderr_path}"]}
      ])

    {:ok,
     %{
       container_ref: "direct-#{spec.run_id}",
       port: port,
       stderr_path: stderr_path,
       workspace_path: spec.workspace_path
     }}
  end

  @impl true
  def stop(handle, _config) do
    try do
      Port.close(handle.port)
    rescue
      _ -> :ok
    end

    :ok
  end

  @impl true
  def cleanup_orphan(_manifest, _config), do: :ok
end
