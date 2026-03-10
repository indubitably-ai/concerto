defmodule Concerto.TestSupport.FakeWorkSource do
  @moduledoc false

  use Agent

  @behaviour Concerto.WorkSource

  def start_link(initial \\ %{dispatch_candidates: [], states: %{}})
  def start_link([]), do: start_link(%{dispatch_candidates: [], states: %{}})

  def start_link(initial) do
    Agent.start_link(fn -> initial end)
  end

  def put_dispatch_candidates(agent, candidates) do
    Agent.update(agent, &Map.put(&1, :dispatch_candidates, candidates))
  end

  def put_states(agent, states) do
    normalized = Map.new(states, fn state -> {state.work_item_id, state} end)
    Agent.update(agent, &Map.put(&1, :states, normalized))
  end

  @impl true
  def fetch_dispatch_candidates(_limit, %{agent: agent}) do
    {:ok, Agent.get(agent, & &1.dispatch_candidates)}
  end

  @impl true
  def fetch_work_item_states(work_item_ids, %{agent: agent}) do
    {:ok,
     Agent.get(agent, fn state ->
       Enum.flat_map(work_item_ids, fn id ->
         case state.states[id] do
           nil -> []
           value -> [value]
         end
       end)
     end)}
  end
end
