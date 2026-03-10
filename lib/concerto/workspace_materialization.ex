defmodule Concerto.WorkspaceMaterialization do
  @moduledoc false

  @enforce_keys [:workspace_key, :workspace_path, :materialized_now, :ready]
  defstruct [:workspace_key, :workspace_path, :materialized_now, :ready]

  @type t :: %__MODULE__{
          workspace_key: String.t(),
          workspace_path: String.t(),
          materialized_now: boolean(),
          ready: boolean()
        }
end
