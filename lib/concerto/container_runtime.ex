defmodule Concerto.ContainerRuntime do
  @moduledoc false

  @type handle :: %{
          container_ref: String.t(),
          port: port(),
          stderr_path: String.t(),
          workspace_path: String.t()
        }

  @callback start_app_server(spec :: map(), config :: map()) :: {:ok, handle()} | {:error, term()}
  @callback stop(handle(), config :: map()) :: :ok | {:error, term()}
  @callback cleanup_orphan(manifest :: map(), config :: map()) :: :ok | {:error, term()}
end
