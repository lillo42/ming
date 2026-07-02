defmodule Ming.Gateway.AMQP.PublisherTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP.Publisher` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.{Basic, Exchange, Queue}
  alias Ming.Gateway.AMQP.Connection, as: AMQPConnection
  alias Ming.Gateway.AMQP.Publisher

  @moduletag :rabbitmq

  defp start_connection(context) do
    name = unique_name(:publisher_connection)

    opts = [
      name: name,
      connection: [uri: rabbit_uri()],
      retry: [max_retries: 1, base_delay: 10]
    ]

    start_supervised!({AMQPConnection, opts})
    Map.put(context, :gateway_name, name)
  end

  defp start_pool(context) do
    pool_name = unique_name(:publisher_pool)
    routing_key = context.routing_key

    worker_opts = [
      name: pool_name,
      gateway_name: context.gateway_name,
      routing_key: routing_key,
      retry: [max_retries: 1, base_delay: 10]
    ]

    pool_opts = [
      name: pool_name,
      worker: {Publisher, worker_opts},
      pool_size: 1
    ]

    start_supervised!(
      %{id: pool_name, start: {NimblePool, :start_link, [pool_opts]}}
    )

    context
    |> Map.put(:pool_name, pool_name)
  end

  setup %{exchange: exchange} do
    context =
      %{
        exchange: exchange,
        routing_key: unique_name(:routing_key)
      }
      |> start_connection()
      |> start_pool()

    [context: context]
  end

  describe "publish/5" do
    test "publishes a message through a pooled channel", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: pool_name, routing_key: routing_key}
    } do
      queue = unique_name(:publisher_queue)
      exchange_str = to_string(exchange)
      routing_key_str = to_string(routing_key)

      :ok = Exchange.declare(chan, exchange_str, :topic, durable: true)
      assert {:ok, _} = Queue.declare(chan, to_string(queue), durable: true)
      :ok = Queue.bind(chan, to_string(queue), exchange_str, routing_key: routing_key_str)

      payload = "hello publisher"

      assert :ok = Publisher.publish(pool_name, exchange_str, routing_key_str, payload, [])
      Process.sleep(100)

      assert {:ok, ^payload, _meta} = Basic.get(chan, to_string(queue), no_ack: true)
    end
  end

  describe "worker lifecycle" do
    test "idle timeout removes idle worker", %{
      context: %{
        gateway_name: gateway_name,
        routing_key: routing_key
      }
    } do
      pool_name = unique_name(:idle_pool)
      exchange_str = to_string(unique_name(:idle_exchange))
      routing_key_str = to_string(routing_key)

      worker_opts = [
        name: pool_name,
        gateway_name: gateway_name,
        routing_key: routing_key,
        idle_timeout: 10,
        retry: [max_retries: 1, base_delay: 10]
      ]

      pool_opts = [
        name: pool_name,
        worker: {Publisher, worker_opts},
        pool_size: 1,
        max_idle_pings: 1
      ]

      start_supervised!(
        %{id: pool_name, start: {NimblePool, :start_link, [pool_opts]}}
      )

      # Trigger a checkout/checkin to create a worker
      assert :ok =
               Publisher.publish(pool_name, exchange_str, routing_key_str, "first", [])

      # Wait for idle ping to remove worker
      Process.sleep(200)

      # A new publish should create a fresh worker (no crash)
      assert :ok =
               Publisher.publish(pool_name, exchange_str, routing_key_str, "second", [])
    end
  end
end
