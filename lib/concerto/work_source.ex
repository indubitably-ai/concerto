defmodule Concerto.WorkSource do
  @moduledoc false

  @callback fetch_dispatch_candidates(limit :: pos_integer(), config :: map()) ::
              {:ok, [Concerto.WorkItem.t()]} | {:error, term()}
  @callback fetch_work_item_states(work_item_ids :: [String.t()], config :: map()) ::
              {:ok, [map()]} | {:error, term()}
end
