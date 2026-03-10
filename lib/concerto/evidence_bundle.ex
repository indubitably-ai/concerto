defmodule Concerto.EvidenceBundle do
  @moduledoc false

  @enforce_keys [
    :scenario_id,
    :layer,
    :command,
    :exit_status,
    :started_at,
    :finished_at,
    :redacted_env,
    :artifacts
  ]
  defstruct [
    :scenario_id,
    :layer,
    :command,
    :exit_status,
    :started_at,
    :finished_at,
    :redacted_env,
    :artifacts
  ]
end
