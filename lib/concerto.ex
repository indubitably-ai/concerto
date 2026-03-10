defmodule Concerto do
  @moduledoc "Concerto runtime entrypoints and helper functions."

  alias Concerto.Bootstrap

  @spec boot(keyword()) :: {:ok, Bootstrap.runtime_context()} | {:error, term()}
  def boot(opts) do
    Bootstrap.boot(opts)
  end
end
