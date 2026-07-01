defmodule Ming.Message.ProducerMessageHandler do
  @moduledoc """
  Handler that publishes a %Ming.Message{} via a configured producer.

  Expects the context assigns to include:
  - `:ming_message_producer` — a module implementing `Ming.Message.Producer`
  - `:ming_message_publication` — publication options for the producer
  """

  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Handler

  @doc """
  Handles internal messaging routing keys.

  For `:ming_produce_message`, it publishes a `%Ming.Message{}` via the
  gateway producer configured in `context.assigns` (`:gateway`,
  `:publication`).

  For `:ming_consume_message`, it dispatches a consumed message through the
  command processor and translates the result into an AMQP
  ack/reject/requeue action.
  """
  @impl Ming.Handler
  def handle(request, context)

  def handle(
        %Message{} = request,
        %Context{
          routing_key: :ming_produce_message,
          assigns: %{
            gateway: gateway,
            publication: publication
          },
          metadata: metadata
        }
      ) do
    extra_opts = Map.get(metadata, :producer_opts, [])

    producer = gateway.producer()

    producer.publish(request,
      gateway: gateway,
      publication: publication,
      extra_opts: extra_opts
    )
  end

  def handle(
        request,
        %Context{
          routing_key: :ming_consume_message,
          metadata: metadata
        }
      ) do
    routing_key = Map.fetch!(metadata, :routing_key)
    command_process = Map.fetch!(metadata, :command_process)

    try do
      case command_process.send(request,
             routing_key: routing_key,
             metadata: metadata
           ) do
        :ok ->
          :ack

        {:ok, _response} ->
          :ack

        :ack ->
          :ack

        :reject ->
          :reject

        :requeue ->
          :requeue

        {:error, _reason} ->
          :reject
      end
    rescue
      _e ->
        :requeue
    end
  end
end
