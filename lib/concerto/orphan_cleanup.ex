defmodule Concerto.OrphanCleanup do
  @moduledoc false

  alias Concerto.{EventLogger, StateStore}

  def cleanup(paths, workflow_root, container_runtime) do
    with {:ok, manifests} <- StateStore.list_ownership_manifests(paths) do
      Enum.each(manifests, fn manifest ->
        if manifest["workflow_root"] == workflow_root do
          apply_runtime(container_runtime, :cleanup_orphan, [manifest])
          if path = manifest["__path__"], do: File.rm(path)
        end
      end)

      EventLogger.emit(paths, :orphan_cleanup, %{"workflow_root" => workflow_root}, %{"count" => length(manifests)})
      :ok
    end
  end

  defp apply_runtime({module, config}, function, args), do: apply(module, function, args ++ [config])
  defp apply_runtime(module, function, args), do: apply(module, function, args ++ [%{}])
end
