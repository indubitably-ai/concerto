defmodule Concerto.WorkSource.Postgres do
  @moduledoc false

  @behaviour Concerto.WorkSource

  alias Concerto.WorkItem

  require Logger

  @impl true
  def fetch_dispatch_candidates(limit, %{dsn: dsn, schema: schema}) do
    query = """
    select work_item_id, workspace_key, dispatch_revision, lifecycle_state, prompt_context, priority
    from #{schema}.dispatch_candidates_view
    limit $1
    """

    with {:ok, rows} <- query(dsn, query, [limit]) do
      {:ok, normalize_rows(rows)}
    end
  end

  @impl true
  def fetch_work_item_states(work_item_ids, %{dsn: dsn, schema: schema}) do
    query = """
    select work_item_id, workspace_key, dispatch_revision, lifecycle_state
    from #{schema}.work_item_states_view
    where work_item_id = any($1)
    """

    with {:ok, rows} <- query(dsn, query, [work_item_ids]) do
      {:ok, normalize_state_rows(rows)}
    end
  end

  defp query(dsn, sql, params) do
    with {:ok, pid} <- Postgrex.start_link(connection_opts(dsn)),
         {:ok, result} <- Postgrex.query(pid, sql, params) do
      GenServer.stop(pid)
      {:ok, rows_to_maps(result)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp connection_opts(dsn) when is_binary(dsn) do
    uri = URI.parse(dsn)
    {username, password} = parse_userinfo(uri.userinfo)
    database = uri.path |> to_string() |> String.trim_leading("/")

    []
    |> maybe_put(:hostname, uri.host)
    |> maybe_put(:port, uri.port)
    |> maybe_put(:username, username)
    |> maybe_put(:password, password)
    |> maybe_put(:database, empty_to_nil(database))
    |> Keyword.merge(query_opts(uri.query))
  end

  defp connection_opts(opts) when is_list(opts), do: opts

  defp parse_userinfo(nil), do: {nil, nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] -> {URI.decode(username), URI.decode(password)}
      [username] -> {URI.decode(username), nil}
    end
  end

  defp query_opts(nil), do: []

  defp query_opts(query) do
    query
    |> URI.decode_query()
    |> Enum.reduce([], fn {key, value}, acc ->
      case query_opt(key, value) do
        nil -> acc
        pair -> [pair | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp query_opt("ssl", value), do: {:ssl, value in ["1", "true", "TRUE", "yes"]}
  defp query_opt("pool_size", value), do: {:pool_size, String.to_integer(value)}
  defp query_opt("timeout", value), do: {:timeout, String.to_integer(value)}
  defp query_opt("connect_timeout", value), do: {:timeout, String.to_integer(value)}
  defp query_opt("socket", value), do: {:socket, value}
  defp query_opt("sslmode", "disable"), do: {:ssl, false}
  defp query_opt("sslmode", _value), do: {:ssl, true}
  defp query_opt(_key, _value), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp rows_to_maps(%Postgrex.Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
  end

  defp normalize_rows(rows) do
    Enum.flat_map(rows, fn row ->
      case WorkItem.normalize(row) do
        {:ok, item} -> [item]
        {:error, reason} ->
          Logger.warning("Skipping invalid dispatch candidate: #{inspect(reason)}")
          []
      end
    end)
  end

  defp normalize_state_rows(rows) do
    Enum.flat_map(rows, fn row ->
      case WorkItem.normalize(Map.put_new(row, "prompt_context", %{})) do
        {:ok, item} ->
          [
            %{
              work_item_id: item.work_item_id,
              workspace_key: item.workspace_key,
              dispatch_revision: item.dispatch_revision,
              lifecycle_state: item.lifecycle_state
            }
          ]

        {:error, reason} ->
          Logger.warning("Skipping invalid lifecycle row: #{inspect(reason)}")
          []
      end
    end)
  end
end
