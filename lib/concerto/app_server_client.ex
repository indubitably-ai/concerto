defmodule Concerto.AppServerClient do
  @moduledoc false

  @callback run_session(spec :: map(), config :: map()) ::
              {:ok,
               %{
                 thread_id: String.t() | nil,
                 last_turn_id: String.t() | nil,
                 turn_count: non_neg_integer(),
                 stop_reason: atom(),
                 status: atom()
               }}
              | {:error, term()}
end
