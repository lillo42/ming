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
    @spec process(
            atom(),
            AMQP.Channel.t(),
            integer(),
            Ming.routing_key(),
            Ming.Message.t(),
            timeout()
          ) ::
            :ok | {:error, any()}

    def process(name, _channel, nil, routing_key, message, timeout) do
      NimblePool.checkout!(
        name,
        :process,
        fn _ref, command_process ->
          result =
            command_process.send(message,
              routing_key: :ming_consume_message,
              metadata: %{routing_key: routing_key},
              timeout: timeout
            )

          {result, command_process}
        end,
        5_000
      )
    catch
      :exit, _reason ->
        {:error, :pool_checkout_timeout}
    end

    def process(name, channel, delivery_tag, routing_key, message, timeout) do
      NimblePool.checkout!(
        name,
        :process,
        fn _ref, command_process ->
          result =
            case command_process.send(message,
                   routing_key: :ming_consume_message,
                   metadata: %{routing_key: routing_key, command_process: command_process},
                   timeout: timeout
                 ) do
              {:ok, :ack} ->
                Basic.ack(channel, delivery_tag)

              {:ok, :reject} ->
                Basic.reject(channel, delivery_tag)

              {:ok, :requeue} ->
                Basic.reject(channel, delivery_tag, requeue: true)

              {:error, _reason} ->
                Basic.reject(channel, delivery_tag)
            end

          {result, command_process}
        end,
        5_000
      )
    catch
      :exit, _reason ->
        Basic.reject(channel, delivery_tag, requeue: true)
        {:error, :pool_checkout_timeout}
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
    def handle_checkin(:ok, _from, worker_state, pool_state) do
      {:ok, worker_state, pool_state}
    end

    def handle_checkin({:error, _reason}, _from, worker_state, pool_state) do
      {:ok, worker_state, pool_state}
    end
  end
end
