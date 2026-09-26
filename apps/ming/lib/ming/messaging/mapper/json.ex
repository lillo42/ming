defmodule Ming.Messaging.Mapper.Json do
  @behaviour Ming.Messaging.Mapper

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Messaging.Mapper
  def to_message(request, %Context{} = context) do
    %Message{
      id: context.id,
      correlation_id: context.correlation_id,
      content_type: "application/json",
      partition_key: resolve_partition_key(context),
      payload: JSON.encode_to_iodata!(request),
      routing_key: context.routing_key,
      timestamp: DateTime.utc_now()
    }
  end

  defp resolve_partition_key(%Context{metadata: %{partition_key: partition_key}}) do
    partition_key
  end

  defp resolve_partition_key(_context), do: nil

  @impl Ming.Messaging.Mapper
  def to_request(%Message{} = message, _context) do
    JSON.decode(message.payload)
  end
end
