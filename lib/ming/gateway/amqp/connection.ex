if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Connection do
    @moduledoc """
    GenServer that holds a single AMQP connection and monitors it.

    On crash the connection is closed gracefully via `terminate/2`.
    """

    use GenServer

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
    """
    @spec get_connection!(atom() | pid()) :: AMQP.Connection.t()
    def get_connection!(name) do
      GenServer.call(name, :get_connection)
    end

    @impl true
    def init(opts) do
      connection = Keyword.fetch!(opts, :connection)

      uri_or_options =
        case Keyword.get(connection, :uri) do
          uri when not is_nil(uri) ->
            uri

          _ ->
            connection
        end

      case AMQP.Connection.open(uri_or_options) do
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

    @impl true
    def terminate(_reason, %{connection: conn}) do
      AMQP.Connection.close(conn)
    end
  end
end
