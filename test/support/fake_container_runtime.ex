defmodule Concerto.TestSupport.FakeContainerRuntime do
  @moduledoc false

  use Agent

  @behaviour Concerto.ContainerRuntime

  def start_link(initial \\ %{starts: [], stops: [], cleanups: []})
  def start_link([]), do: start_link(%{starts: [], stops: [], cleanups: []})

  def start_link(initial) do
    Agent.start_link(fn -> initial end)
  end

  def state(agent), do: Agent.get(agent, & &1)

  @impl true
  def start_app_server(spec, %{agent: agent}) do
    Agent.update(agent, &update_in(&1.starts, fn starts -> [spec | starts] end))
    File.write!(Path.join(spec.run_dir, "stderr.txt"), "")

    {:ok,
     %{
       container_ref: "fake-#{spec.run_id}",
       port: nil,
       stderr_path: Path.join(spec.run_dir, "stderr.txt"),
       workspace_path: spec.workspace_path
     }}
  end

  @impl true
  def stop(handle, %{agent: agent}) do
    if Process.alive?(agent) do
      Agent.update(agent, &update_in(&1.stops, fn stops -> [handle | stops] end))
    end

    :ok
  end

  @impl true
  def cleanup_orphan(manifest, %{agent: agent}) do
    if Process.alive?(agent) do
      Agent.update(agent, &update_in(&1.cleanups, fn cleanups -> [manifest | cleanups] end))
    end

    :ok
  end
end
