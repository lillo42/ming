defmodule Ming.Gateway.AMQP.MessageProcess do
  @moduledoc """
  NimblePool worker that dispatches a consumed AMQP message into the
  Ming command pipeline and acks / rejects the delivery based on the result.
  """

  alias AMQP.Basic

  alias Ming.Message

  @behaviour NimblePool

  @doc """
  Checks out a worker from the pool and sends the message through the
  configured command processor. The AMQP delivery is acknowledged,
  rejected, or requeued depending on the handler result.

  When the `:requeue_count` option is set, requeues are no longer
  broker-native: the message is republished to the `:queue` option with an
  incremented `x-ming-requeue-count` header and the original delivery is
  acked; once the count reaches `:requeue_count` the delivery is rejected
  without requeue so the broker dead-letters it instead of looping forever.
  """
  @spec process(
          atom(),
          AMQP.Channel.t(),
          integer(),
          Ming.routing_key(),
          Ming.Message.t(),
          timeout(),
          keyword()
        ) ::
          :ok | {:error, any()}

  def process(name, channel, delivery_tag, routing_key, message, timeout, opts \\ [])

  def process(name, _channel, nil, routing_key, message, timeout, _opts) do
    NimblePool.checkout!(
      name,
      :process,
      fn _ref, command_process ->
        result =
          command_process.send(message,
            routing_key: :ming_consume_message,
            metadata: %{routing_key: routing_key, command_process: command_process},
            timeout: timeout
          )

        {result, command_process}
      end,
      :infinity
    )
  catch
    :exit, _reason ->
      {:error, :process_timeout}
  end

  def process(name, channel, delivery_tag, routing_key, message, timeout, opts) do
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
              Basic.reject(channel, delivery_tag, requeue: false)

            {:ok, {:reject, _reason}} ->
              Basic.reject(channel, delivery_tag, requeue: false)

            {:reject, _reason} ->
              Basic.reject(channel, delivery_tag, requeue: false)

            {:ok, :requeue} ->
              requeue(channel, delivery_tag, message, opts)

            {:error, _reason} ->
              Basic.reject(channel, delivery_tag, requeue: false)
          end

        {result, command_process}
      end,
      :infinity
    )
  catch
    :exit, _reason ->
      requeue(channel, delivery_tag, message, opts)
      {:error, :process_timeout}
  end

  # Without a :requeue_count limit the broker-native requeue is used
  defp requeue(channel, delivery_tag, message, opts) do
    case Keyword.get(opts, :requeue_count) do
      max_requeues when is_integer(max_requeues) ->
        capped_requeue(channel, delivery_tag, message, opts, max_requeues)

      _no_limit ->
        Basic.reject(channel, delivery_tag, requeue: true)
    end
  end

  defp capped_requeue(channel, delivery_tag, message, opts, max_requeues) do
    count = Message.requeue_count(message)

    if count >= max_requeues do
      # over the limit: reject without requeue so the broker dead-letters
      # the message instead of requeueing it forever
      Basic.reject(channel, delivery_tag, requeue: false)
    else
      republish(channel, Keyword.fetch!(opts, :queue), message, count + 1)
      Basic.ack(channel, delivery_tag)
    end
  end

  # A native requeue cannot carry the incremented counter, so the message
  # is republished to its own queue with an updated requeue-count header
  # and the original delivery is acked
  defp republish(channel, queue, %Message{} = message, count) do
    metadata = Map.get(message.headers, :amqp_metadata, %{})
    count_header = Message.requeue_count_header()

    headers =
      metadata
      |> Map.get(:headers, [])
      |> List.wrap()
      |> Enum.reject(fn
        {key, _type, _value} -> key == count_header
        _other -> false
      end)
      |> Kernel.++([{count_header, :long, count}])

    opts =
      [
        headers: headers,
        content_type: message.content_type,
        message_id: message.id,
        correlation_id: message.correlation_id,
        persistent: Map.get(metadata, :persistent, true)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    Basic.publish(channel, "", queue, message.payload, opts)
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

  def handle_checkin(_result, _from, worker_state, pool_state) do
    {:ok, worker_state, pool_state}
  end
end
