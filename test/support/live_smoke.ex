defmodule Concerto.TestSupport.LiveSmoke do
  @moduledoc false

  alias Concerto.{Bootstrap, EventLogger}
  alias Concerto.TestSupport.{Evidence, Temp}

  @runner_image System.get_env("CONCERTO_RUNNER_IMAGE") || "concerto-codex-runner:latest"
  @postgres_image "postgres:16-alpine"

  def ensure_runner_image! do
    case System.cmd("docker", ["image", "inspect", @runner_image], stderr_to_stdout: true) do
      {_output, 0} ->
        @runner_image

      _ ->
        build_runner_image!()
        @runner_image
    end
  end

  def start_postgres! do
    {output, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "-d",
          "--rm",
          "-e",
          "POSTGRES_USER=concerto",
          "-e",
          "POSTGRES_PASSWORD=secret",
          "-e",
          "POSTGRES_DB=app",
          "-p",
          "127.0.0.1::5432",
          @postgres_image
        ],
        stderr_to_stdout: true
      )

    container_id = String.trim(output)
    port = wait_for_postgres_port!(container_id)
    dsn = "postgres://concerto:secret@127.0.0.1:#{port}/app"
    wait_for_postgres_ready!(dsn)
    %{container_id: container_id, dsn: dsn}
  end

  def stop_postgres(%{container_id: container_id}) do
    System.cmd("docker", ["rm", "-f", container_id], stderr_to_stdout: true)
    :ok
  end

  def openai_profile! do
    auth_json = Path.expand("~/.codex/auth.json")

    cond do
      present?(System.get_env("OPENAI_API_KEY")) ->
        %{
          runner_env: %{"OPENAI_API_KEY" => System.fetch_env!("OPENAI_API_KEY")},
          runner_auth_mounts: []
        }

      File.exists?(auth_json) ->
        %{
          runner_env: %{},
          runner_auth_mounts: [%{source: auth_json, target: "/tmp/codex-home/auth.json"}]
        }

      true ->
        raise "OPENAI_API_KEY or ~/.codex/auth.json is not configured; this target environment is not smoke-complete"
    end
  end

  def bedrock_profile!(scratch_root) do
    config_path = write_bedrock_config!(scratch_root)
    auth_json = Path.expand("~/.codex/indubitably-auth.json")

    token =
      System.get_env("INDUBITABLY_API_TOKEN") ||
        System.get_env("BEDROCK_BEARER_TOKEN") ||
        System.get_env("INDUBITABLY_BEARER_TOKEN") ||
        maybe_read_indubitably_token(auth_json)

    mounts =
      [%{source: config_path, target: "/tmp/codex-home/config.toml"}]
      |> maybe_append_mount(File.exists?(auth_json), %{
        source: auth_json,
        target: "/tmp/codex-home/indubitably-auth.json"
      })

    env =
      %{}
      |> maybe_put_env("INDUBITABLY_API_TOKEN", token)
      |> maybe_put_env("BEDROCK_BEARER_TOKEN", System.get_env("BEDROCK_BEARER_TOKEN"))
      |> maybe_put_env("INDUBITABLY_BEARER_TOKEN", System.get_env("INDUBITABLY_BEARER_TOKEN"))

    if present?(token) or File.exists?(auth_json) do
      %{runner_env: env, runner_auth_mounts: mounts}
    else
      raise "BEDROCK_BEARER_TOKEN, INDUBITABLY_BEARER_TOKEN, or ~/.codex/indubitably-auth.json is not configured; this target environment is not smoke-complete"
    end
  end

  def direct_aws_profile!(scratch_root) do
    config_path = write_direct_aws_config!(scratch_root)

    env =
      %{
        "AWS_REGION" => System.get_env("AWS_REGION") || "us-east-1",
        "AWS_ACCESS_KEY_ID" =>
          System.get_env("AWS_ACCESS_KEY_ID") || "concerto-smoke-placeholder",
        "AWS_SECRET_ACCESS_KEY" =>
          System.get_env("AWS_SECRET_ACCESS_KEY") || "concerto-smoke-placeholder"
      }
      |> maybe_put_env("AWS_SESSION_TOKEN", System.get_env("AWS_SESSION_TOKEN"))

    %{
      runner_env: env,
      runner_auth_mounts: [%{source: config_path, target: "/tmp/codex-home/config.toml"}]
    }
  end

  def prepare_runtime!(scenario_id, pg, profile, opts \\ []) do
    schema = schema_name(scenario_id)
    workspace_root = Temp.tmp_dir!("workspace-#{scenario_id}")
    workflow_root = workflow_root!(scenario_id, pg.dsn, schema, workspace_root, opts)

    work_item = %{
      work_item_id: "wi-#{String.downcase(scenario_id)}",
      workspace_key: "repo-#{String.downcase(scenario_id)}",
      dispatch_revision: "rev-1",
      lifecycle_state: "dispatchable",
      prompt_context: %{
        "target_file" => "#{String.downcase(scenario_id)}.txt",
        "target_contents" => "#{scenario_id} smoke validation"
      },
      priority: 1
    }

    seed_views!(pg.dsn, schema, work_item)

    profile_config =
      case profile do
        :openai -> openai_profile!()
        :bedrock -> bedrock_profile!(workflow_root)
        :direct_aws -> direct_aws_profile!(workflow_root)
      end

    {:ok, runtime} =
      Bootstrap.boot(
        workflow_root: workflow_root,
        runner_image: @runner_image,
        runner_env: profile_config.runner_env,
        runner_auth_mounts: profile_config.runner_auth_mounts
      )

    expected_path =
      Path.join([
        workspace_root,
        work_item.workspace_key,
        work_item.prompt_context["target_file"]
      ])

    %{
      runtime: runtime,
      workflow_root: workflow_root,
      workspace_root: workspace_root,
      work_item: work_item,
      expected_path: expected_path
    }
  end

  def wait_for_attempt!(paths, timeout_ms \\ 180_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_attempt(paths, deadline)
  end

  def assert_completed!(attempt, expected_path, expected_contents) do
    if attempt["status"] != "completed" do
      raise "expected completed attempt, got #{inspect(attempt)}"
    end

    unless File.read!(expected_path) == expected_contents do
      raise "expected #{expected_path} to contain #{inspect(expected_contents)}"
    end

    :ok
  end

  def assert_failed!(attempt) do
    if attempt["status"] == "completed" do
      raise "expected failed attempt, got #{inspect(attempt)}"
    end

    :ok
  end

  def copy_run_artifacts(bundle, paths, attempt) do
    bundle
    |> Evidence.copy_artifact(
      "structured_log",
      EventLogger.structured_log_path(paths),
      "structured.log"
    )
    |> Evidence.copy_artifact(
      "run_attempt",
      Path.join(paths.run_state_root, "#{attempt["run_id"]}.json"),
      "run-attempt.json"
    )
    |> maybe_copy_run_file(
      "app_server_transcript",
      Path.join([paths.runs_root, attempt["run_id"], "app-server-transcript.jsonl"]),
      "app-server-transcript.jsonl"
    )
    |> maybe_copy_run_file(
      "stderr",
      Path.join([paths.runs_root, attempt["run_id"], "stderr.txt"]),
      "stderr.txt"
    )
  end

  defp build_runner_image! do
    script = Path.expand("scripts/build-runner-image", File.cwd!())

    case System.cmd(script, [], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "runner image build failed with status #{status}: #{output}"
    end
  end

  defp wait_for_postgres_port!(container_id, attempts \\ 30)

  defp wait_for_postgres_port!(_container_id, 0),
    do: raise("postgres container did not publish a port")

  defp wait_for_postgres_port!(container_id, attempts) do
    case System.cmd("docker", ["port", container_id, "5432/tcp"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/:(\d+)\s*$/m, output, capture: :all_but_first) do
          [port] ->
            String.to_integer(port)

          _ ->
            Process.sleep(1_000)
            wait_for_postgres_port!(container_id, attempts - 1)
        end

      _ ->
        Process.sleep(1_000)
        wait_for_postgres_port!(container_id, attempts - 1)
    end
  end

  defp wait_for_postgres_ready!(dsn, attempts \\ 60)
  defp wait_for_postgres_ready!(_dsn, 0), do: raise("postgres container did not become ready")

  defp wait_for_postgres_ready!(dsn, attempts) do
    case Postgrex.start_link(connection_opts(dsn)) do
      {:ok, pid} ->
        case Postgrex.query(pid, "select 1", []) do
          {:ok, _result} ->
            GenServer.stop(pid)
            :ok

          {:error, _reason} ->
            GenServer.stop(pid)
            Process.sleep(1_000)
            wait_for_postgres_ready!(dsn, attempts - 1)
        end

      {:error, _reason} ->
        Process.sleep(1_000)
        wait_for_postgres_ready!(dsn, attempts - 1)
    end
  end

  defp workflow_root!(scenario_id, dsn, schema, workspace_root, _opts) do
    body = """
    ---
    work_source:
      dsn: #{dsn}
      schema: #{schema}
    workspace:
      root: #{workspace_root}
    polling:
      interval_ms: 250
    agent:
      max_concurrent_agents: 1
    ---
    # Concerto Smoke Workflow

    Create the file named by `prompt_context.target_file` in the repository root.
    Write exactly the bytes from `prompt_context.target_contents`.
    Do not append a trailing newline.
    Do not ask for input. Stop after the file exists with the requested contents.
    """

    Temp.workflow_root!("smoke-#{String.downcase(scenario_id)}", body)
  end

  defp seed_views!(dsn, schema, work_item) do
    {:ok, pid} = Postgrex.start_link(connection_opts(dsn))

    prompt_context =
      work_item.prompt_context
      |> Jason.encode!()
      |> String.replace("'", "''")

    statements = [
      "drop schema if exists #{schema} cascade",
      "create schema #{schema}",
      """
      create view #{schema}.dispatch_candidates_view as
      select
        '#{work_item.work_item_id}'::text as work_item_id,
        '#{work_item.workspace_key}'::text as workspace_key,
        '#{work_item.dispatch_revision}'::text as dispatch_revision,
        '#{work_item.lifecycle_state}'::text as lifecycle_state,
        '#{prompt_context}'::jsonb as prompt_context,
        #{work_item.priority}::integer as priority
      """,
      """
      create view #{schema}.work_item_states_view as
      select
        '#{work_item.work_item_id}'::text as work_item_id,
        '#{work_item.workspace_key}'::text as workspace_key,
        '#{work_item.dispatch_revision}'::text as dispatch_revision,
        '#{work_item.lifecycle_state}'::text as lifecycle_state
      """
    ]

    try do
      Enum.each(statements, &Postgrex.query!(pid, &1, []))
    after
      GenServer.stop(pid)
    end
  end

  defp do_wait_for_attempt(paths, deadline_ms) do
    run_files = Path.wildcard(Path.join(paths.run_state_root, "*.json"))

    attempt =
      Enum.find_value(run_files, fn file ->
        case Jason.decode(File.read!(file)) do
          {:ok, %{"status" => status} = payload}
          when status in ["completed", "failed", "canceled_by_reconciliation"] ->
            payload

          _ ->
            nil
        end
      end)

    cond do
      attempt ->
        attempt

      System.monotonic_time(:millisecond) >= deadline_ms ->
        raise "timed out waiting for smoke attempt in #{paths.run_state_root}"

      true ->
        Process.sleep(1_000)
        do_wait_for_attempt(paths, deadline_ms)
    end
  end

  defp write_bedrock_config!(scratch_root) do
    path = Path.join(scratch_root, "bedrock-config.toml")

    File.write!(
      path,
      """
      model = "claude-3-5-sonnet"
      approval_policy = "never"
      model_provider = "bedrock"

      [model_providers.bedrock]
      name = "AWS Bedrock"
      base_url = "https://api.indubitably.ai"
      env_key = "INDUBITABLY_API_TOKEN"
      """
    )

    path
  end

  defp write_direct_aws_config!(scratch_root) do
    path = Path.join(scratch_root, "direct-aws-config.toml")

    File.write!(
      path,
      """
      model = "claude-3-5-sonnet"
      approval_policy = "never"
      model_provider = "bedrock"

      [model_providers.bedrock]
      name = "AWS Bedrock"
      base_url = "https://bedrock-runtime.us-east-1.amazonaws.com"
      """
    )

    path
  end

  defp connection_opts(dsn) do
    uri = URI.parse(dsn)
    {username, password} = parse_userinfo(uri.userinfo)

    [
      hostname: uri.host,
      port: uri.port,
      username: username,
      password: password,
      database: String.trim_leading(uri.path || "", "/")
    ]
  end

  defp parse_userinfo(nil), do: {nil, nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] -> {URI.decode(username), URI.decode(password)}
      [username] -> {URI.decode(username), nil}
    end
  end

  defp maybe_read_indubitably_token(path) do
    with true <- File.exists?(path),
         {:ok, body} <- File.read(path),
         {:ok, %{"entries" => entries}} <- Jason.decode(body),
         %{"access_token" => token} when is_binary(token) <-
           Map.get(entries, "https://api.indubitably.ai"),
         true <- present?(token) do
      token
    else
      _ -> nil
    end
  end

  defp schema_name(scenario_id) do
    suffix = System.unique_integer([:positive]) |> Integer.to_string()
    "smoke_#{String.downcase(String.replace(scenario_id, "-", "_"))}_#{suffix}"
  end

  defp maybe_copy_run_file(bundle, logical_name, path, filename) do
    if File.exists?(path) do
      Evidence.copy_artifact(bundle, logical_name, path, filename)
    else
      bundle
    end
  end

  defp maybe_append_mount(list, true, mount), do: [mount | list]
  defp maybe_append_mount(list, false, _mount), do: list

  defp maybe_put_env(map, _key, nil), do: map
  defp maybe_put_env(map, key, value), do: Map.put(map, key, value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
