if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.MessageProcess do
    alias AMQP.Basic

    @behaviour NimblePool

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
  end
end
