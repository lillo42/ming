defmodule Ming.Gateway.InMemory.Consumer do
  @moduledoc """
  GenServer that consumes messages from the in-memory broker and dispatches
  them through the configured command processor.

  Each consumer subscribes to a single routing key. When a message arrives,
  it is handed to `command_processor.send/2` using the
  `:ming_consume_message` routing key, matching the AMQP consumer semantics.
  """

  use GenServer

  alias Ming.Gateway.InMemory
  alias Ming.Gateway.InMemory.Broker

  @doc """
  Starts the consumer linked to the current process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(args) do
    gateway_name = Keyword.fetch!(args, :gateway_name)
    routing_key = Keyword.fetch!(args, :routing_key)
    command_processor = Keyword.fetch!(args, :command_processor)
    subscription = Keyword.get(args, :subscription, [])

    broker_name = InMemory.broker_name(gateway_name)

    replay_on_start = Keyword.get(subscription, :replay_on_start, false)

    :ok = Broker.subscribe(broker_name, routing_key, replay_on_start)

    {:ok,
     %{
       broker_name: broker_name,
       command_processor: command_processor,
       routing_key: routing_key,
       timeout: Keyword.get(subscription, :processing_timeout, :infinity)
     }}
  end

  @impl true
  def terminate(_reason, state) do
    try do
      Broker.unsubscribe(state.broker_name, state.routing_key)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  @impl true
  def handle_info({:in_memory_message, routing_key, message}, state) do
    command_processor = state.command_processor

    result =
      command_processor.send(message,
        routing_key: :ming_consume_message,
        metadata: %{routing_key: routing_key, command_process: command_processor},
        timeout: state.timeout
      )

    case result do
      :ok -> :ok
      {:ok, _response} -> :ok
      :ack -> :ok
      :reject -> :ok
      :requeue -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
