if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Connection do
    @moduledoc """
    GenServer that holds a single AMQP connection and monitors it.

    On crash the connection is closed gracefully via `terminate/2`.
    """

    use GenServer

    alias Ming.Gateway.RetryConfig

    require Logger

    @doc """
    Starts the connection holder linked to the current process.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @doc """
    Returns the underlying `%AMQP.Connection{}` struct.
    Verifies the connection is alive before returning.
    """
    @spec get_connection!(atom() | pid()) :: AMQP.Connection.t()
    def get_connection!(name) do
      conn = GenServer.call(name, :get_connection)

      if Process.alive?(conn.pid) do
        conn
      else
        # Connection is stale, wait for restart and retry once
        Process.sleep(100)
        conn = GenServer.call(name, :get_connection)

        if Process.alive?(conn.pid) do
          conn
        else
          raise "AMQP connection is not alive"
        end
      end
    end

    @impl true
    def init(opts) do
      connection = Keyword.fetch!(opts, :connection)
      retry_config = RetryConfig.new(Keyword.get(opts, :retry, []))

      uri_or_options =
        case Keyword.get(connection, :uri) do
          uri when not is_nil(uri) ->
            uri

          _ ->
            connection
        end

      case connect_with_backoff(uri_or_options, retry_config, 0) do
        {:ok, conn} ->
          Process.monitor(conn.pid)
          {:ok, %{connection: conn}}

        {:error, reason} ->
          {:stop, reason}
      end
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
      {:stop, :connection_lost, state}
    end

    @impl true
    def handle_call(:get_connection, _from, %{connection: conn} = state) do
      {:reply, conn, state}
    end

    defp connect_with_backoff(uri_or_options, retry_config, attempt)
         when attempt < retry_config.max_retries do
      case AMQP.Connection.open(uri_or_options) do
        {:ok, conn} ->
          {:ok, conn}

        {:error, reason} ->
          delay = RetryConfig.calculate_delay(retry_config, attempt)

          Logger.warning(
            "AMQP connection attempt #{attempt + 1} failed: #{inspect(reason)}, retrying in #{delay}ms"
          )

          Process.sleep(delay)
          connect_with_backoff(uri_or_options, retry_config, attempt + 1)
      end
    end

    defp connect_with_backoff(_uri_or_options, _retry_config, _attempt) do
      {:error, :max_connection_attempts_exceeded}
    end

    @impl true
    def terminate(_reason, %{connection: conn}) do
      AMQP.Connection.close(conn)
    end
  end
end
