defmodule Concerto.WorkspaceMaterializer do
  @moduledoc false

  @callback materialize(
              workflow_root :: String.t(),
              workspace_key :: String.t(),
              workspace_path :: String.t(),
              paths :: map(),
              options :: map()
            ) :: {:ok, Concerto.WorkspaceMaterialization.t()} | {:error, term()}
end
