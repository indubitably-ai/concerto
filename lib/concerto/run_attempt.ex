defmodule Concerto.RunAttempt do
  @moduledoc false

  alias Concerto.TraceContext

  @enforce_keys [
    :run_id,
    :work_item_id,
    :workspace_key,
    :dispatch_revision,
    :workspace_path,
    :turn_count,
    :trace,
    :started_at,
    :status,
    :stop_reason
  ]
  defstruct [
    :run_id,
    :work_item_id,
    :workspace_key,
    :dispatch_revision,
    :workspace_path,
    :thread_id,
    :last_turn_id,
    :turn_count,
    :trace,
    :started_at,
    :finished_at,
    :stop_reason,
    :status
  ]

  @type status :: :completed | :failed | :canceled_by_reconciliation

  @type t :: %__MODULE__{
          run_id: String.t(),
          work_item_id: String.t(),
          workspace_key: String.t(),
          dispatch_revision: String.t(),
          workspace_path: String.t(),
          thread_id: String.t() | nil,
          last_turn_id: String.t() | nil,
          turn_count: non_neg_integer(),
          trace: TraceContext.t(),
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          stop_reason: atom(),
          status: status()
        }
end
