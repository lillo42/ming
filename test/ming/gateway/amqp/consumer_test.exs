defmodule Ming.Gateway.AMQP.ConsumerTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP.Consumer` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.{Basic, Exchange, Queue}
  alias Ming.Gateway.AMQP.Connection, as: AMQPConnection
  alias Ming.Gateway.AMQP.Consumer
  alias Ming.Message

  alias Ming.Gateway.AMQP.MessageProcess

  @moduletag :rabbitmq

  defp start_gateway(%{exchange: _exchange}) do
    gateway_name = unique_name(:consumer_gateway)

    start_supervised!(
      {AMQPConnection,
       name: gateway_name,
       connection: [uri: rabbit_uri()],
       retry: [max_retries: 1, base_delay: 10]}
    )

    gateway_name
  end

  defp declare_queue(chan, exchange, routing_key) do
    queue = unique_name(:consumer_queue)
    queue_str = to_string(queue)
    exchange_str = to_string(exchange)

    try do
      Queue.delete(chan, queue_str)
    catch
      _, _ -> :ok
    end

    :ok = Exchange.declare(chan, exchange_str, :topic, durable: true)
    assert {:ok, _} = Queue.declare(chan, queue_str, durable: true)

    :ok =
      Queue.bind(chan, queue_str, exchange_str, routing_key: to_string(routing_key))

    on_exit(fn ->
      try do
        Queue.delete(chan, queue_str)
        Exchange.delete(chan, exchange_str)
      catch
        _, _ -> :ok
      end
    end)

    queue
  end

  setup %{exchange: exchange, amqp_chan: chan} do
    gateway_name = start_gateway(%{exchange: exchange})
    routing_key = unique_name(:consumer_rk)
    queue = declare_queue(chan, exchange, routing_key)

    Application.put_env(:ming, :amqp_test_target_pid, self())

    consumer_name = unique_name(:consumer)
    process_pool_name = unique_name(:consumer_process_pool)

    start_supervised!(%{
      id: process_pool_name,
      start:
        {NimblePool, :start_link,
         [
           [
             name: process_pool_name,
             worker: {MessageProcess, command_process: TestAMQPProcessor},
             pool_size: 1
           ]
         ]}
    })

    start_supervised!(
      {Consumer,
       name: consumer_name,
       gateway_name: gateway_name,
       topic_or_queue: queue,
       routing_key: routing_key,
       process_pool_name: process_pool_name,
       command_processor: TestAMQPProcessor,
       buffer_size: 1,
       number_of_performers: 1}
    )

    on_exit(fn ->
      Application.delete_env(:ming, :amqp_test_target_pid)
    end)

    [
      gateway_name: gateway_name,
      routing_key: routing_key,
      queue: queue,
      process_pool_name: process_pool_name
    ]
  end

  describe "message delivery" do
    test "consumer receives a published message", %{
      amqp_chan: chan,
      exchange: exchange,
      routing_key: routing_key
    } do
      payload = "hello consumer"

      :ok =
        Basic.publish(
          chan,
          to_string(exchange),
          to_string(routing_key),
          payload,
          message_id: "recv-1",
          content_type: "text/plain"
        )

      assert_receive {:consumed, %Message{payload: ^payload} = message, _opts}, 2_000
      assert message.id == "recv-1"
      assert message.content_type == "text/plain"
      assert message.routing_key == routing_key
    end

    test "to_message/3 parses CloudEvents headers", %{
      amqp_chan: chan,
      exchange: exchange,
      routing_key: routing_key
    } do
      headers = [
        {"cloudEvents:id", :longstr, "ce-1"},
        {"cloudEvents:type", :longstr, "com.example.event"},
        {"cloudEvents:source", :longstr, "https://example.com/source"},
        {"cloudEvents:subject", :longstr, "subject-1"}
      ]

      :ok =
        Basic.publish(
          chan,
          to_string(exchange),
          to_string(routing_key),
          "cloud event",
          headers: headers,
          message_id: "ignored"
        )

      assert_receive {:consumed, %Message{} = message, _opts}, 2_000

      assert message.id == "ce-1"
      assert message.type == "com.example.event"
      assert message.source == URI.new!("https://example.com/source")
      assert message.subject == "subject-1"
    end

    test "to_message/3 falls back to defaults when headers are absent", %{
      amqp_chan: chan,
      exchange: exchange,
      routing_key: routing_key
    } do
      :ok =
        Basic.publish(
          chan,
          to_string(exchange),
          to_string(routing_key),
          "plain event",
          message_id: "fallback-id"
        )

      assert_receive {:consumed, %Message{} = message, _opts}, 2_000

      assert message.id == "fallback-id"
      assert message.spec_version == "1.0"
      assert message.source == URI.new!("https://hex.pm/packages/ming")
      assert message.timestamp.__struct__ == DateTime
    end

    test "to_message/3 parses AMQP table and array headers", %{
      amqp_chan: chan,
      exchange: exchange,
      routing_key: routing_key
    } do
      headers = [
        {"x-table", :table, [{"nested", :longstr, "value"}]},
        {"x-array", :array, [{:longstr, "a"}, {:longstr, "b"}]}
      ]

      :ok =
        Basic.publish(
          chan,
          to_string(exchange),
          to_string(routing_key),
          "structured headers",
          headers: headers
        )

      assert_receive {:consumed, %Message{} = message, _opts}, 2_000

      assert message.headers["x-table"] == %{"nested" => "value"}
      assert message.headers["x-array"] == ["a", "b"]
    end
  end

  describe "lifecycle" do
    test "stops when the queue is deleted", %{
      amqp_chan: chan,
      queue: queue,
      gateway_name: gateway_name,
      routing_key: routing_key
    } do
      consumer_name = unique_name(:cancel_consumer)
      process_pool_name = unique_name(:cancel_process_pool)

      start_supervised!(%{
        id: process_pool_name,
        start:
          {NimblePool, :start_link,
           [
             [
               name: process_pool_name,
               worker: {MessageProcess, command_process: TestAMQPProcessor},
               pool_size: 1
             ]
           ]}
      })

      pid =
        start_supervised!(%{
          id: consumer_name,
          start:
            {Consumer, :start_link,
             [
               [
                 name: consumer_name,
                 gateway_name: gateway_name,
                 topic_or_queue: queue,
                 routing_key: routing_key,
                 process_pool_name: process_pool_name,
                 command_processor: TestAMQPProcessor,
                 buffer_size: 1,
                 number_of_performers: 1
               ]
             ]}
        })

      ref = Process.monitor(pid)

      assert {:ok, _} = Queue.delete(chan, to_string(queue))

      assert_receive {:DOWN, ^ref, :process, ^pid, :stopped_by_amqp}, 2_000
    end
  end
end
