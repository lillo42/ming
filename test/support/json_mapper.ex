defmodule Ming.JsonMapper do
  @behaviour Ming.MessageMapper

  alias Ming.Message

  def to_map(%Message{} = message) do
    Jason.decoded!(message.payload)
  end

  def to_message(map) do
    %Message{
      id: map[:id] || to_string(System.unique_integer()),
      message_type: :command,
      source: URI.parse("/ming"),
      routing_key: map[:routing_key] || "test",
      payload: Jason.encode!(map),
      time_stamp: DateTime.utc_now()
    }
  end
end
