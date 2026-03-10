defmodule Concerto.TraceContext do
  @moduledoc false

  @enforce_keys [:trace_id, :span_id]
  defstruct [:trace_id, :span_id, :parent_span_id, :causation_id]

  @type t :: %__MODULE__{
          trace_id: String.t(),
          span_id: String.t(),
          parent_span_id: String.t() | nil,
          causation_id: String.t() | nil
        }

  def root do
    %__MODULE__{
      trace_id: token(),
      span_id: token(),
      parent_span_id: nil,
      causation_id: nil
    }
  end

  def child(%__MODULE__{} = trace, causation_id \\ nil) do
    %__MODULE__{
      trace_id: trace.trace_id,
      span_id: token(),
      parent_span_id: trace.span_id,
      causation_id: causation_id
    }
  end

  defp token do
    12 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
