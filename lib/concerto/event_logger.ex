defmodule Concerto.EventLogger do
  @moduledoc false

  alias Concerto.RuntimeEvent

  require Logger

  def emit(paths, name, metadata, measurements \\ %{}) do
    event = RuntimeEvent.new(name, metadata, measurements)

    case RuntimeEvent.validate(event) do
      :ok ->
        write(paths, event)

      {:error, reason} ->
        violation =
          RuntimeEvent.new(:event_contract_violation, %{"error" => inspect(reason), "attempted_event" => Atom.to_string(name)}, %{})

        write(paths, violation)
    end
  end

  def structured_log_path(paths), do: Path.join(paths.runs_root, "structured.log")

  defp write(paths, event) do
    File.mkdir_p!(paths.runs_root)

    encoded =
      event
      |> Map.from_struct()
      |> Map.update!(:timestamp, &DateTime.to_iso8601/1)
      |> Jason.encode_to_iodata!()

    File.write!(structured_log_path(paths), [encoded, "\n"], [:append])
    Logger.info(fn -> "#{event.name} #{inspect(event.metadata)}" end)
    :ok
  end
end
