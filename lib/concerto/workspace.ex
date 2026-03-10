defmodule Concerto.Workspace do
  @moduledoc false

  @enforce_keys [:workspace_key, :path, :created_now, :materialized_now]
  defstruct [:workspace_key, :path, :created_now, :materialized_now]

  @type t :: %__MODULE__{
          workspace_key: String.t(),
          path: String.t(),
          created_now: boolean(),
          materialized_now: boolean()
        }
end
