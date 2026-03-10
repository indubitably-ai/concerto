defmodule Concerto.DispatchPolicy do
  @moduledoc false

  alias Concerto.{StateStore, WorkItem}

  def eligible_candidates(candidates, running, paths) do
    Enum.filter(candidates, fn %WorkItem{} = candidate ->
      candidate.lifecycle_state == :dispatchable and
        not Map.has_key?(running, candidate.work_item_id) and
        last_revision_changed?(paths, candidate)
    end)
  end

  def sort_candidates(candidates) do
    Enum.sort_by(candidates, fn candidate ->
      {candidate.priority || :infinity, candidate.work_item_id}
    end)
  end

  def continuation_allowed?(work_source, work_item) do
    {module, config} =
      case work_source do
        {source_module, source_config} -> {source_module, source_config}
        source_module -> {source_module, %{}}
      end

    case module.fetch_work_item_states([work_item.work_item_id], config) do
      {:ok, [%{lifecycle_state: :dispatchable, dispatch_revision: revision}]} ->
        revision == work_item.dispatch_revision

      _ ->
        false
    end
  end

  def last_revision_changed?(paths, %WorkItem{} = candidate) do
    case StateStore.last_terminal_revision(paths, candidate.work_item_id) do
      {:ok, revision} -> revision != candidate.dispatch_revision
      :not_found -> true
      {:error, _reason} -> true
    end
  end
end
