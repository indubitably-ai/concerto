defmodule Concerto.WorkflowConfig do
  @moduledoc false

  @enforce_keys [:work_source, :workspace, :polling, :agent]
  defstruct [:work_source, :workspace, :polling, :agent]

  @type t :: %__MODULE__{
          work_source: %{dsn: String.t(), schema: String.t()},
          workspace: %{root: String.t()},
          polling: %{interval_ms: pos_integer()},
          agent: %{max_concurrent_agents: pos_integer()}
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(front_matter) when is_map(front_matter) do
    with {:ok, dsn} <- fetch_string(front_matter, ["work_source", "dsn"]),
         {:ok, schema} <- fetch_string(front_matter, ["work_source", "schema"]),
         {:ok, root} <- fetch_string(front_matter, ["workspace", "root"]),
         {:ok, interval_ms} <- fetch_positive_integer(front_matter, ["polling", "interval_ms"], 30_000),
         {:ok, max_agents} <-
           fetch_positive_integer(front_matter, ["agent", "max_concurrent_agents"], 1) do
      {:ok,
       %__MODULE__{
         work_source: %{dsn: dsn, schema: schema},
         workspace: %{root: root},
         polling: %{interval_ms: interval_ms},
         agent: %{max_concurrent_agents: max_agents}
       }}
    end
  end

  defp fetch_string(map, path) do
    case get_in(map, path) do
      value when is_binary(value) ->
        value = String.trim(value)

        if byte_size(value) > 0 do
          {:ok, value}
        else
          {:error, {:invalid_workflow_field, Enum.join(path, ".")}}
        end

      _ ->
        {:error, {:invalid_workflow_field, Enum.join(path, ".")}}
    end
  end

  defp fetch_positive_integer(map, path, default) do
    case get_in(map, path) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      _ ->
        {:error, {:invalid_workflow_field, Enum.join(path, ".")}}
    end
  end
end
