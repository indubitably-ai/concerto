defmodule Concerto.RuntimeConstants do
  @moduledoc false

  @turn_cap 5
  @attempt_timeout_ms :timer.minutes(15)
  @response_timeout_ms :timer.seconds(30)
  @stderr_cap_bytes 1_048_576

  def turn_cap, do: @turn_cap
  def attempt_timeout_ms, do: @attempt_timeout_ms
  def response_timeout_ms, do: @response_timeout_ms
  def stderr_cap_bytes, do: @stderr_cap_bytes
end
