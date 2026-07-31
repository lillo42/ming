defmodule Ming.Gateway.AMQP.ProducerTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP.Producer` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.{Basic, Exchange, Queue}
  alias Ming.Gateway.AMQP.Connection, as: AMQPConnection
  alias Ming.Gateway.AMQP.Producer
  alias Ming.Message

  @moduletag :rabbitmq

  defp amqp_headers_to_map(headers) do
    headers
    |> Enum.map(fn {key, _type, value} -> {key, value} end)
    |> Map.new()
  end

  defp start_pool(context) do
    pool_name = context.routing_key

    worker_opts = [
      name: pool_name,
      gateway_name: context.gateway_name,
      routing_key: context.routing_key,
      retry: [max_retries: 1, base_delay: 10]
    ]

    pool_opts = [
      name: pool_name,
      worker: {Ming.Gateway.AMQP.Publisher, worker_opts},
      pool_size: 1
    ]

    start_supervised!(%{id: pool_name, start: {NimblePool, :start_link, [pool_opts]}})

    Map.put(context, :pool_name, pool_name)
  end

  setup %{exchange: exchange} do
    gateway_name = unique_name(:producer_gateway)

    start_supervised!(
      {AMQPConnection,
       name: gateway_name,
       connection: [uri: rabbit_uri()],
       retry: [max_retries: 1, base_delay: 10]}
    )

    routing_key = unique_name(:producer_rk)

    context = %{
      gateway_name: gateway_name,
      exchange: exchange,
      routing_key: routing_key,
      pool_name: nil
    }

    context = start_pool(context)

    [context: context]
  end

  defp declare_and_bind(%{amqp_chan: chan, exchange: exchange, context: context}) do
    queue = unique_name(:producer_queue)
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
      Queue.bind(chan, queue_str, exchange_str, routing_key: to_string(context.routing_key))

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

  describe "publish/2" do
    test "publishes a single message", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      message = %Message{
        id: "msg-1",
        payload: "hello producer",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic],
        app_id: "ming_test"
      ]

      publication = [
        routing_key: routing_key,
        persistent: true,
        mandatory: false
      ]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "hello producer", meta} = Basic.get(chan, to_string(queue), no_ack: true)
      assert meta.exchange == to_string(exchange)
      assert meta.routing_key == to_string(routing_key)
      assert meta.message_id == "msg-1"
    end

    test "publishes a list of messages", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      messages =
        for i <- 1..3 do
          %Message{
            id: "msg-#{i}",
            payload: "payload-#{i}",
            routing_key: routing_key,
            timestamp: DateTime.utc_now()
          }
        end

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key]

      assert [_, _, _] =
               Producer.publish(messages, gateway: gateway_config, publication: publication)

      Process.sleep(100)

      for i <- 1..3 do
        assert {:ok, payload, _meta} = Basic.get(chan, to_string(queue), no_ack: true)
        assert payload == "payload-#{i}"
      end
    end

    test "publishes iodata payloads as binary", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      # The default JSON mapper produces iodata, not a binary
      message = %Message{
        id: "iodata-msg",
        payload: ["hello ", ["io", "data"]],
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "hello iodata", _meta} = Basic.get(chan, to_string(queue), no_ack: true)
    end

    test "injects CloudEvents headers in binary mode", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      message = %Message{
        id: "ce-msg",
        payload: "cloud event",
        routing_key: routing_key,
        timestamp: ~U[2024-01-01T12:00:00Z],
        type: "com.example.event",
        source: "https://example.com/source",
        subject: "test-subject",
        correlation_id: "corr-1"
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key, cloudevent_mode: :binary]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "cloud event", meta} = Basic.get(chan, to_string(queue), no_ack: true)
      headers = amqp_headers_to_map(meta.headers || [])

      assert headers["cloudEvents:id"] == "ce-msg"
      assert headers["cloudEvents:type"] == "com.example.event"
      assert headers["cloudEvents:source"] == "https://example.com/source"
      assert headers["cloudEvents:subject"] == "test-subject"
      assert headers["cloudEvents:specversion"] == "1.0"
      assert String.starts_with?(headers["cloudEvents:time"], "2024-01-01T12:00:00")
    end

    test "preserves message headers in json mode", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      message = %Message{
        id: "json-msg",
        payload: "json event",
        routing_key: routing_key,
        timestamp: DateTime.utc_now(),
        headers: %{"x-custom" => "custom-value"}
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key, cloudevent_mode: :json]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "json event", meta} = Basic.get(chan, to_string(queue), no_ack: true)
      headers = amqp_headers_to_map(meta.headers || [])

      assert headers["x-custom"] == "custom-value"
      refute Map.has_key?(headers, "cloudEvents:id")
    end

    test "preserves non-ASCII custom header values", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      message = %Message{
        id: "utf8-msg",
        payload: "utf8",
        routing_key: routing_key,
        timestamp: DateTime.utc_now(),
        headers: %{"x-custom" => "café résumé"}
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key, cloudevent_mode: :json]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "utf8", meta} = Basic.get(chan, to_string(queue), no_ack: true)
      headers = amqp_headers_to_map(meta.headers || [])

      assert headers["x-custom"] == "café résumé"
    end

    test "merges default headers", %{
      amqp_chan: chan,
      exchange: exchange,
      context: %{pool_name: _pool_name, routing_key: routing_key}
    } do
      queue =
        declare_and_bind(%{
          amqp_chan: chan,
          exchange: exchange,
          context: %{routing_key: routing_key}
        })

      message = %Message{
        id: "defaults-msg",
        payload: "defaults",
        routing_key: routing_key,
        timestamp: DateTime.utc_now(),
        headers: %{"x-custom" => "message-value"}
      }

      gateway_config = [
        adapter: Ming.Gateway.AMQP,
        name: :unused,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [
        routing_key: routing_key,
        cloudevent_mode: :json,
        default_headers: %{"x-default" => "default-value", "x-custom" => "default-custom"}
      ]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)
      Process.sleep(100)

      assert {:ok, "defaults", meta} = Basic.get(chan, to_string(queue), no_ack: true)
      headers = amqp_headers_to_map(meta.headers || [])

      assert headers["x-default"] == "default-value"
      assert headers["x-custom"] == "message-value"
    end
  end
end
