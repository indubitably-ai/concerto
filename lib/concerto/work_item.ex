defmodule Concerto.WorkItem do
  @moduledoc false

  @workspace_key ~r/\A[A-Za-z0-9._-]+\z/

  @enforce_keys [:work_item_id, :workspace_key, :dispatch_revision, :lifecycle_state, :prompt_context]
  defstruct [:work_item_id, :workspace_key, :dispatch_revision, :lifecycle_state, :prompt_context, :priority]

  @type lifecycle_state :: :dispatchable | :inactive | :terminal

  @type t :: %__MODULE__{
          work_item_id: String.t(),
          workspace_key: String.t(),
          dispatch_revision: String.t(),
          lifecycle_state: lifecycle_state(),
          prompt_context: map(),
          priority: integer() | nil
        }

  @spec normalize(map()) :: {:ok, t()} | {:error, term()}
  def normalize(row) when is_map(row) do
    with {:ok, work_item_id} <- require_text(row, ["work_item_id"]),
         {:ok, workspace_key} <- validate_workspace_key(row),
         {:ok, dispatch_revision} <- require_text(row, ["dispatch_revision"]),
         {:ok, lifecycle_state} <- normalize_lifecycle(get_value(row, "lifecycle_state")),
         {:ok, prompt_context} <- normalize_prompt_context(get_value(row, "prompt_context")),
         {:ok, priority} <- normalize_priority(get_value(row, "priority")) do
      {:ok,
       %__MODULE__{
         work_item_id: work_item_id,
         workspace_key: workspace_key,
         dispatch_revision: dispatch_revision,
         lifecycle_state: lifecycle_state,
         prompt_context: prompt_context,
         priority: priority
       }}
    end
  end

  def to_prompt_json(%__MODULE__{} = item) do
    %{
      "work_item_id" => item.work_item_id,
      "workspace_key" => item.workspace_key,
      "dispatch_revision" => item.dispatch_revision,
      "lifecycle_state" => Atom.to_string(item.lifecycle_state),
      "prompt_context" => item.prompt_context,
      "priority" => item.priority
    }
  end

  defp require_text(row, [key]) do
    case get_value(row, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if byte_size(value) > 0 do
          {:ok, value}
        else
          {:error, {:invalid_field, key}}
        end

      _ ->
        {:error, {:invalid_field, key}}
    end
  end

  defp validate_workspace_key(row) do
    with {:ok, key} <- require_text(row, ["workspace_key"]),
         true <- Regex.match?(@workspace_key, key) do
      {:ok, key}
    else
      false -> {:error, {:invalid_field, "workspace_key"}}
      error -> error
    end
  end

  defp normalize_lifecycle(value) do
    case value do
      "dispatchable" -> {:ok, :dispatchable}
      "inactive" -> {:ok, :inactive}
      "terminal" -> {:ok, :terminal}
      atom when atom in [:dispatchable, :inactive, :terminal] -> {:ok, atom}
      _ -> {:error, {:invalid_field, "lifecycle_state"}}
    end
  end

  defp normalize_prompt_context(nil), do: {:ok, %{}}
  defp normalize_prompt_context(map) when is_map(map), do: {:ok, map}
  defp normalize_prompt_context(_), do: {:error, {:invalid_field, "prompt_context"}}

  defp normalize_priority(nil), do: {:ok, nil}
  defp normalize_priority(value) when is_integer(value), do: {:ok, value}
  defp normalize_priority(value) when is_float(value), do: {:ok, trunc(value)}
  defp normalize_priority(_), do: {:error, {:invalid_field, "priority"}}

  defp get_value(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end
end
