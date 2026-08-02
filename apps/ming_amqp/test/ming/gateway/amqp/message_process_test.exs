defmodule Ming.Gateway.AMQP.MessageProcessTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP.MessageProcess` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.{Basic, Exchange, Queue}
  alias Ming.Gateway.AMQP.MessageProcess
  alias Ming.Message

  @moduletag :rabbitmq

  defmodule TestCommandProcessor do
    @moduledoc false
    use Agent

    import Kernel, except: [send: 2]

    def start_link(_), do: Agent.start_link(fn -> :ack end, name: __MODULE__)

    def set_result(result), do: Agent.update(__MODULE__, fn _ -> result end)

    def send(message, opts) do
      action = Agent.get(__MODULE__, fn state -> state end)
      result = if action == :boom, do: {:error, :boom}, else: {:ok, action}
      pid = Application.fetch_env!(:ming, :amqp_test_target_pid)
      Kernel.send(pid, {:processed, message, opts, result})
      result
    end
  end

  setup %{amqp_conn: conn, amqp_chan: chan, exchange: _exchange} do
    start_supervised!(TestCommandProcessor)
    Application.put_env(:ming, :amqp_test_target_pid, self())

    pool_name = unique_name(:message_process_pool)

    start_supervised!(%{
      id: pool_name,
      start:
        {NimblePool, :start_link,
         [
           [
             name: pool_name,
             worker: {MessageProcess, command_process: TestCommandProcessor},
             pool_size: 1
           ]
         ]}
    })

    on_exit(fn -> Application.delete_env(:ming, :amqp_test_target_pid) end)

    [
      pool_name: pool_name,
      consumer_chan: chan,
      consumer_conn: conn
    ]
  end

  defp setup_queue(%{amqp_chan: chan, exchange: exchange}) do
    queue = unique_name(:mp_queue)
    routing_key = unique_name(:mp_rk)
    queue_str = to_string(queue)
    exchange_str = to_string(exchange)

    # Ensure a clean queue even if a previous test run left a durable queue behind.
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

    {queue, routing_key}
  end

  describe "process/6" do
    test ":ack removes message from queue",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "ack me")
      Process.sleep(100)
      assert {:ok, "ack me", meta} = Basic.get(chan, to_string(queue))

      message = %Message{
        id: "ack-msg",
        payload: "ack me",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:ack)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity
               )

      assert {:empty, _} = Basic.get(chan, to_string(queue))
      assert_receive {:processed, ^message, _opts, {:ok, :ack}}, 1_000
    end

    test ":reject removes message from queue",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "reject me")
      Process.sleep(100)
      assert {:ok, "reject me", meta} = Basic.get(chan, to_string(queue))

      message = %Message{
        id: "reject-msg",
        payload: "reject me",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:reject)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity
               )

      assert {:empty, _} = Basic.get(chan, to_string(queue))
    end

    test ":requeue keeps message in queue",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "requeue me")
      Process.sleep(100)
      assert {:ok, "requeue me", meta} = Basic.get(chan, to_string(queue))

      message = %Message{
        id: "requeue-msg",
        payload: "requeue me",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:requeue)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity
               )

      assert {:ok, "requeue me", _meta} = Basic.get(chan, to_string(queue))
    end

    test ":requeue republishes with an incremented counter when :requeue_count is set",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)
      queue_str = to_string(queue)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "requeue me")
      Process.sleep(100)
      assert {:ok, "requeue me", meta} = Basic.get(chan, queue_str)

      message = %Message{
        id: "requeue-count-msg",
        payload: "requeue me",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:requeue)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity,
                 queue: queue_str,
                 requeue_count: 3
               )

      assert {:ok, "requeue me", republished_meta} = Basic.get(chan, queue_str)

      assert {"x-ming-requeue-count", :long, 1} =
               Enum.find(republished_meta.headers, fn {key, _type, _val} ->
                 key == "x-ming-requeue-count"
               end)
    end

    test ":requeue rejects the message when the requeue count is reached",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "poison")
      Process.sleep(100)
      assert {:ok, "poison", meta} = Basic.get(chan, to_string(queue))

      message = %Message{
        id: "poison-msg",
        payload: "poison",
        routing_key: routing_key,
        timestamp: DateTime.utc_now(),
        headers: %{"x-ming-requeue-count" => 3}
      }

      TestCommandProcessor.set_result(:requeue)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity,
                 queue: to_string(queue),
                 requeue_count: 3
               )

      assert {:empty, _} = Basic.get(chan, to_string(queue))
    end

    test "{:error, _} rejects message",
         %{amqp_chan: chan, exchange: exchange, pool_name: pool_name} = context do
      {queue, routing_key} = setup_queue(context)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "error me")
      Process.sleep(100)
      assert {:ok, "error me", meta} = Basic.get(chan, to_string(queue))

      message = %Message{
        id: "error-msg",
        payload: "error me",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:boom)

      assert :ok =
               MessageProcess.process(
                 pool_name,
                 chan,
                 meta.delivery_tag,
                 routing_key,
                 message,
                 :infinity
               )

      assert {:empty, _} = Basic.get(chan, to_string(queue))
    end

    test "nil delivery_tag processes without AMQP ack", %{pool_name: pool_name} do
      message = %Message{
        id: "nil-tag",
        payload: "no ack",
        routing_key: :test,
        timestamp: DateTime.utc_now()
      }

      TestCommandProcessor.set_result(:ack)

      assert {:ok, :ack} =
               MessageProcess.process(pool_name, :ignored, nil, :test, message, :infinity)

      assert_receive {:processed, ^message, _opts, {:ok, :ack}}, 1_000
    end
  end
end
