defmodule Ming.MessageTest do
  use ExUnit.Case

  alias Ming.Message

  describe "struct" do
    test "requires id, payload, routing_key and timestamp" do
      assert_raise ArgumentError, fn ->
        struct!(Message, payload: "data", routing_key: :test)
      end
    end

    test "can be constructed with all enforced keys" do
      now = DateTime.utc_now()

      message =
        struct!(Message,
          id: "msg-1",
          payload: "data",
          routing_key: :test,
          timestamp: now
        )

      assert message.id == "msg-1"
      assert message.payload == "data"
      assert message.routing_key == :test
      assert message.timestamp == now
    end

    test "applies default field values" do
      message =
        struct!(Message,
          id: "msg-1",
          payload: "data",
          routing_key: :test,
          timestamp: DateTime.utc_now()
        )

      assert message.content_type == "text/plain"
      assert message.headers == %{}
      assert message.spec_version == "1.0"
    end
  end
end
