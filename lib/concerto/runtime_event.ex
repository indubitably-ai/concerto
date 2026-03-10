defmodule Concerto.RuntimeEvent do
  @moduledoc false

  @required_names [
    :startup_succeeded,
    :startup_failed,
    :dispatch_started,
    :workspace_created,
    :workspace_reused,
    :workspace_materialized,
    :workspace_materialization_skipped,
    :container_launched,
    :session_started,
    :turn_started,
    :turn_completed,
    :turn_failed,
    :turn_interrupted,
    :attempt_completed,
    :attempt_failed,
    :reconciliation_stop,
    :orphan_cleanup,
    :postgres_read_failed,
    :event_contract_violation
  ]

  @enforce_keys [:name, :timestamp, :metadata, :measurements]
  defstruct [:name, :timestamp, :metadata, :measurements]

  @type t :: %__MODULE__{
          name: atom(),
          timestamp: DateTime.t(),
          metadata: map(),
          measurements: map()
        }

  def required_names, do: @required_names

  def new(name, metadata, measurements \\ %{}) do
    %__MODULE__{
      name: name,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      measurements: measurements
    }
  end

  def validate(%__MODULE__{} = event) do
    cond do
      event.name not in @required_names -> {:error, :unknown_event_name}
      not is_map(event.metadata) -> {:error, :invalid_metadata}
      not is_map(event.measurements) -> {:error, :invalid_measurements}
      not match?(%DateTime{}, event.timestamp) -> {:error, :invalid_timestamp}
      true -> :ok
    end
  end
end
