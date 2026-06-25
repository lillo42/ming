if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Publisher do
    alias AMQP.Basic
    alias AMQP.Channel

    alias Ming.Gateway.AMQP.Connection

    @behaviour NimblePool

    def publish(pool_name, exchange, routing_key, payload, opts) do
      NimblePool.checkout!(pool_name, :publish, fn _ref, channel ->
        result = Basic.publish(channel, exchange, routing_key, payload, opts)
        {result, channel}
      end)
    end

    @impl NimblePool
    def init_pool(args) do
      name = Keyword.fetch!(args, :gateway_name)
      conn = Connection.get_connection!(name)

      {:ok, %{connection: conn, publication: args}}
    end

    @impl NimblePool
    def init_worker(%{connection: conn} = state) do
      {:ok, channel} = Channel.open(conn)
      {:ok, %{channel: channel, last_usage: DateTime.utc_now()}, state}
    end

    @impl NimblePool
    def handle_checkout(:publish, _from, %{channel: channel} = worker_state, pool_state) do
      if Process.alive?(channel.pid) do
        {:ok, channel, Map.put(worker_state, :last_usage, DateTime.utc_now()), pool_state}
      else
        {:remove, :dead, pool_state}
      end
    end

    @impl NimblePool
    def terminate_worker(_reason, %{channel: channel}, pool_state) do
      try do
        Channel.close(channel)
      rescue
        _e -> nil
      catch
        _e -> nil
      end

      {:ok, pool_state}
    end

    @impl NimblePool
    def handle_ping(%{last_usage: last_usage} = worker_state, %{publication: publication}) do
      timeout = Keyword.get(publication, :idle_timeout, :infinity)
      now = DateTime.utc_now()

      if timeout == :infinity or DateTime.diff(now, last_usage) < timeout do
        {:ok, worker_state}
      else
        {:remove, :idle_timeout}
      end
    end
  end
end
