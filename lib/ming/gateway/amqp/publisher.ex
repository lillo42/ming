if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Publisher do
    @moduledoc """
    NimblePool worker that manages a pool of AMQP channels for publishing.

    Channels are checked out per-publish, kept alive while in use, and closed
    when the worker is terminated or idle for too long.
    """

    alias AMQP.Basic
    alias AMQP.Channel

    alias Ming.Gateway.AMQP.Connection

    @behaviour NimblePool

    @doc """
    Publishes a message through a pooled AMQP channel.
    """
    @spec publish(atom(), String.t(), String.t(), binary(), keyword()) ::
            :ok | {:error, any()}
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
      case Channel.open(conn) do
        {:ok, channel} ->
          {:ok, %{channel: channel, last_usage: DateTime.utc_now()}, state}

        {:error, reason} ->
          {:remove, {:channel_open_failed, reason}}
      end
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
    def handle_checkin(:ok, _from, _worker_state, pool_state) do
      {:ok, pool_state}
    end

    def handle_checkin({:error, _reason}, _from, _worker_state, pool_state) do
      {:ok, pool_state}
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

      if timeout == :infinity or DateTime.diff(now, last_usage, :millisecond) < timeout do
        {:ok, worker_state}
      else
        {:remove, :idle_timeout}
      end
    end
  end
end
