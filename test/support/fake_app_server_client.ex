defmodule Concerto.TestSupport.FakeAppServerClient do
  @moduledoc false

  @behaviour Concerto.AppServerClient

  @impl true
  def run_session(_spec, config) do
    case config[:mode] do
      :complete ->
        {:ok, %{thread_id: "thr_fake", last_turn_id: "turn_fake", turn_count: 1, stop_reason: :turn_completed, status: :completed}}

      :timeout ->
        {:ok, %{thread_id: "thr_fake", last_turn_id: "turn_fake", turn_count: 1, stop_reason: :timeout, status: :failed}}

      :block_until_cancel ->
        receive do
          {:concerto_cancel, :reconciliation, _state} ->
            {:ok,
             %{
               thread_id: "thr_fake",
               last_turn_id: "turn_fake",
               turn_count: 1,
               stop_reason: :reconciliation,
               status: :canceled_by_reconciliation
             }}
        after
          2_000 ->
            {:ok, %{thread_id: "thr_fake", last_turn_id: "turn_fake", turn_count: 1, stop_reason: :turn_completed, status: :completed}}
        end

      {:sleep, ms} ->
        Process.sleep(ms)
        {:ok, %{thread_id: "thr_fake", last_turn_id: "turn_fake", turn_count: 1, stop_reason: :turn_completed, status: :completed}}
    end
  end
end
