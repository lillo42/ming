if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.MessageProcess do
    @moduledoc """
    NimblePool worker that dispatches a consumed AMQP message into the
    Ming command pipeline and acks / rejects the delivery based on the result.
    """

    alias AMQP.Basic

    @behaviour NimblePool

    @doc """
    Checks out a worker from the pool and sends the message through the
    configured command processor. The AMQP delivery is acknowledged,
    rejected, or requeued depending on the handler result.
    """
    @spec process(atom(), AMQP.Channel.t(), integer(), Ming.routing_key(), Ming.Message.t(), timeout()) ::
            :ok | {:error, any()}
    def process(name, channel, delivery_tag, routing_key, message, timeout) do
      NimblePool.checkout!(name, :process, fn _ref, command_process ->
        result =
          case command_process.send(message, routing_key: routing_key, timeout: timeout) do
            :ack ->
              Basic.ack(channel, delivery_tag)

            :reject ->
              Basic.reject(channel, delivery_tag)

            :requeue ->
              Basic.reject(channel, delivery_tag, requeue: true)

            {:error, _reason} ->
              Basic.reject(channel, delivery_tag, requeue: true)
          end

        {result, command_process}
      end)
    end

    @impl NimblePool
    def init_pool(arg), do: {:ok, %{command_process: Keyword.fetch!(arg, :command_process)}}

    @impl NimblePool
    def init_worker(pool_state), do: {:ok, pool_state, pool_state}

    @impl NimblePool
    def handle_checkout(
          :process,
          _from,
          %{command_process: command_process} = worker_state,
          pool_state
        ) do
      {:ok, command_process, worker_state, pool_state}
    end

    @impl NimblePool
    def handle_checkin(:ok, _from, _worker_state, pool_state) do
      {:ok, pool_state}
    end

    def handle_checkin({:error, _reason}, _from, _worker_state, pool_state) do
      {:ok, pool_state}
    end
  end
end
