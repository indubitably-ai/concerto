defmodule Concerto.ContainerRuntime.DockerCLI do
  @moduledoc false

  @behaviour Concerto.ContainerRuntime

  @impl true
  def start_app_server(spec, config) do
    docker = Map.get(config, :docker_executable, System.find_executable("docker") || "docker")
    container_ref = "concerto-#{spec.run_id}"
    stderr_path = Path.join(spec.run_dir, "stderr.txt")
    File.write!(stderr_path, "")

    shell = System.find_executable("sh") || "/bin/sh"

    port =
      Port.open({:spawn_executable, shell}, [
        :binary,
        :exit_status,
        {:line, 1_048_576},
        {:args, ["-lc", docker_command(docker, spec, container_ref, stderr_path)]}
      ])

    {:ok,
     %{
       container_ref: container_ref,
       port: port,
       stderr_path: stderr_path,
       workspace_path: spec.workspace_path,
       container_workspace_path: "/workspace",
       container_codex_home: "/tmp/codex-home"
     }}
  end

  @impl true
  def stop(handle, _config) do
    try do
      Port.close(handle.port)
    rescue
      _ -> :ok
    end

    System.cmd("docker", ["rm", "-f", handle.container_ref], stderr_to_stdout: true)
    truncate_stderr(handle.stderr_path)
    :ok
  end

  @impl true
  def cleanup_orphan(manifest, _config) do
    if ref = manifest["container_ref"] do
      System.cmd("docker", ["rm", "-f", ref], stderr_to_stdout: true)
    end

    :ok
  end

  defp docker_command(docker, spec, container_ref, stderr_path) do
    env_flags =
      Enum.map(spec.runner_env, fn {key, value} ->
        "-e #{escape_arg(key)}=#{escape_arg(value)}"
      end)

    auth_mounts =
      Enum.map(spec.runner_auth_mounts, fn %{source: source, target: target} ->
        "-v #{escape_arg(Path.expand(source))}:#{escape_arg(target)}:ro"
      end)

    label_flags =
      [
        "concerto.owner=concerto",
        "concerto.run_id=#{spec.run_id}",
        "concerto.work_item_id=#{spec.work_item.work_item_id}",
        "concerto.workspace_key=#{spec.work_item.workspace_key}",
        "concerto.workflow_root=#{Path.expand(Path.dirname(spec.workflow_path))}"
      ]
      |> Enum.map(&"--label #{escape_arg(&1)}")

    [
      docker,
      "run --rm -i --name #{escape_arg(container_ref)}",
      "-v #{escape_arg(spec.workspace_path)}:/workspace",
      "-v #{escape_arg(spec.workflow_path)}:/workflow/WORKFLOW.md:ro",
      Enum.join(label_flags, " "),
      Enum.join(auth_mounts, " "),
      Enum.join(env_flags, " "),
      "-e CODEX_HOME=/tmp/codex-home",
      escape_arg(spec.runner_image),
      "sh -lc 'mkdir -p /tmp/codex-home && exec codex --dangerously-bypass-approvals-and-sandbox app-server'",
      "2>>#{escape_arg(stderr_path)}"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp truncate_stderr(path) do
    case File.read(path) do
      {:ok, contents} ->
        limit = Concerto.RuntimeConstants.stderr_cap_bytes()

        if byte_size(contents) > limit do
          File.write!(path, binary_part(contents, 0, limit))
        end

      _ ->
        :ok
    end
  end

  defp escape_arg(value) do
    value
    |> to_string()
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end
end
