defmodule Concerto.Bootstrap do
  @moduledoc false

  alias Concerto.{
    EventLogger,
    OrphanCleanup,
    RuntimeConfig,
    SystemPaths,
    WorkflowLoader
  }

  @type runtime_context :: RuntimeConfig.t()

  def boot(opts) do
    workflow_root = Keyword.fetch!(opts, :workflow_root)
    work_source = Keyword.get(opts, :work_source, {Concerto.WorkSource.Postgres, %{}})

    materializer =
      Keyword.get(opts, :workspace_materializer, {Concerto.WorkspaceMaterializer.Copying, %{}})

    container_runtime =
      Keyword.get(opts, :container_runtime, {Concerto.ContainerRuntime.DockerCLI, %{}})

    app_server_client =
      Keyword.get(opts, :app_server_client, {Concerto.AppServerClient.Stdio, %{}})

    runner_env = Keyword.get(opts, :runner_env, default_runner_env())
    runner_auth_mounts = Keyword.get(opts, :runner_auth_mounts, [])

    runner_image =
      Keyword.get(
        opts,
        :runner_image,
        Application.get_env(:concerto, :runner_image, "concerto-codex-runner:latest")
      )

    with {:ok, workflow} <- WorkflowLoader.load(workflow_root) do
      paths = SystemPaths.build(workflow_root)
      SystemPaths.ensure!(paths)
      :ok = OrphanCleanup.cleanup(paths, workflow_root, container_runtime)

      EventLogger.emit(paths, :startup_succeeded, %{"workflow_root" => workflow_root}, %{})

      {:ok,
       %RuntimeConfig{
         workflow: workflow,
         paths: paths,
         work_source: merge_runtime_config(work_source, workflow.config.work_source),
         workspace_materializer: materializer,
         container_runtime: container_runtime,
         app_server_client: app_server_client,
         runner_image: runner_image,
         runner_env: runner_env,
         runner_auth_mounts: runner_auth_mounts
       }}
    else
      {:error, reason} ->
        paths = SystemPaths.build(workflow_root)
        SystemPaths.ensure!(paths)

        EventLogger.emit(
          paths,
          :startup_failed,
          %{"workflow_root" => workflow_root, "error" => inspect(reason)},
          %{}
        )

        {:error, reason}
    end
  end

  defp merge_runtime_config({module, config}, workflow_config),
    do: {module, Map.merge(workflow_config, config)}

  defp merge_runtime_config(module, workflow_config), do: {module, workflow_config}

  defp default_runner_env do
    System.get_env()
    |> Enum.filter(fn {key, _value} ->
      key in [
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "ANTHROPIC_API_KEY",
        "AWS_REGION",
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "INDUBITABLY_API_TOKEN",
        "BEDROCK_BEARER_TOKEN",
        "INDUBITABLY_BEARER_TOKEN"
      ]
    end)
    |> Map.new()
  end
end
