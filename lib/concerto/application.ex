defmodule Concerto.Application do
  @moduledoc false

  use Application

  alias Concerto.Bootstrap

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Concerto.WorkerRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Concerto.WorkerSupervisor}
    ]

    children =
      case runtime_context() do
        {:ok, runtime} -> children ++ [{Concerto.Orchestrator, runtime}]
        :disabled -> children
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Concerto.Supervisor)
  end

  defp runtime_context do
    case Application.get_env(:concerto, :workflow_root) do
      nil ->
        :disabled

      workflow_root ->
        runtime_opts =
          Application.get_env(:concerto, :runtime_overrides, [])
          |> Keyword.put(:workflow_root, workflow_root)

        Bootstrap.boot(runtime_opts)
    end
  end
end
