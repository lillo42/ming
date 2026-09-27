defmodule Ming.Messaging.Mapper.Json do
  @moduledoc """
  Maps requests to and from JSON payloads using the built-in `JSON` module.

  This is the default mapper, resolved from the `:json` shorthand.

  ## Options

    * `:encoder` — a custom recursive encoder function passed as the second
      argument to `JSON.encode!/2`, defaults to `JSON.protocol_encode/2`
    * `:decoders` — decoder hooks passed as the third argument to
      `JSON.decode/3` (e.g. `[object_push: fn key, value, acc -> ... end]`),
      defaults to `[]`

  A payload that cannot be decoded raises `Ming.InvalidMessageError`.
  """

  @behaviour Ming.Messaging.Mapper

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Messaging.Mapper
  def to_message(request, %Context{} = context, args) do
    %Message{
      id: context.id,
      correlation_id: context.correlation_id,
      content_type: "application/json",
      partition_key: resolve_partition_key(context),
      payload: encode(request, Keyword.get(args || [], :encoder)),
      routing_key: context.routing_key,
      timestamp: DateTime.utc_now()
    }
  end

  defp encode(request, nil), do: JSON.encode_to_iodata!(request)
  defp encode(request, encoder), do: JSON.encode_to_iodata!(request, encoder)

  @impl Ming.Messaging.Mapper
  def to_request(%Message{} = message, _context, args) do
    case JSON.decode(message.payload, [], Keyword.get(args || [], :decoders, [])) do
      {request, _acc, _rest} ->
        {:ok, request}

      {:error, reason} ->
        raise Ming.InvalidMessageError,
          message: "the message payload could not be decoded as JSON",
          reason: reason
    end
  end

  defp resolve_partition_key(%Context{metadata: %{partition_key: partition_key}}) do
    partition_key
  end

  defp resolve_partition_key(_context), do: nil
end
