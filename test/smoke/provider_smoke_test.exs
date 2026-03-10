defmodule Concerto.Smoke.ProviderSmokeTest do
  use ExUnit.Case, async: false

  alias Concerto.TestSupport.Evidence
  alias Concerto.TestSupport.LiveSmoke

  @moduletag :smoke

  setup_all do
    image = LiveSmoke.ensure_runner_image!()
    pg = LiveSmoke.start_postgres!()
    on_exit(fn -> LiveSmoke.stop_postgres(pg) end)
    {:ok, runner_image: image, pg: pg}
  end

  test "ACC-12 OpenAI baseline smoke completes through the supported Concerto path", %{pg: pg} do
    bundle = Evidence.start!("ACC-12", "Smoke", starts_codex: true)
    smoke = LiveSmoke.prepare_runtime!("ACC-12", pg, :openai)

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, smoke.runtime})
    attempt = LiveSmoke.wait_for_attempt!(smoke.runtime.paths)

    :ok =
      LiveSmoke.assert_completed!(
        attempt,
        smoke.expected_path,
        smoke.work_item.prompt_context["target_contents"]
      )

    bundle = LiveSmoke.copy_run_artifacts(bundle, smoke.runtime.paths, attempt)
    Evidence.log(bundle, "OpenAI smoke completed with a real containerized run.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-13 Bedrock proxy smoke completes through the supported Concerto path", %{pg: pg} do
    bundle = Evidence.start!("ACC-13", "Smoke", starts_codex: true)
    smoke = LiveSmoke.prepare_runtime!("ACC-13", pg, :bedrock)

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, smoke.runtime})
    attempt = LiveSmoke.wait_for_attempt!(smoke.runtime.paths)

    :ok =
      LiveSmoke.assert_completed!(
        attempt,
        smoke.expected_path,
        smoke.work_item.prompt_context["target_contents"]
      )

    bundle = LiveSmoke.copy_run_artifacts(bundle, smoke.runtime.paths, attempt)
    Evidence.log(bundle, "Bedrock proxy smoke completed with a real containerized run.")
    Evidence.finish!(bundle, 0)
  end

  test "ACC-14 direct AWS Bedrock remains an explicit unsupported path", %{pg: pg} do
    bundle = Evidence.start!("ACC-14", "Smoke", starts_codex: true)
    smoke = LiveSmoke.prepare_runtime!("ACC-14", pg, :direct_aws)

    {:ok, _pid} = start_supervised({Concerto.Orchestrator, smoke.runtime})
    attempt = LiveSmoke.wait_for_attempt!(smoke.runtime.paths)

    :ok = LiveSmoke.assert_failed!(attempt)

    bundle = LiveSmoke.copy_run_artifacts(bundle, smoke.runtime.paths, attempt)
    Evidence.log(bundle, "Direct AWS Bedrock failed as the unsupported base-v1 path.")
    Evidence.finish!(bundle, 0)
  end
end
