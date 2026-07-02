defmodule Ming.Gateway.AMQPTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.{Basic, Exchange, Queue}
  alias Ming.Gateway.AMQP
  alias Ming.Gateway.AMQP.Producer
  alias Ming.Message

  @moduletag :rabbitmq

  setup do
    Application.put_env(:ming, :amqp_test_target_pid, self())
    on_exit(fn -> Application.delete_env(:ming, :amqp_test_target_pid) end)
    :ok
  end

  describe "start_link/1 and init/1" do
    test "starts supervisor with connection, publishers, consumers and pools" do
      name = unique_name(:amqp_gateway)

      opts = [
        name: name,
        command_processor: TestAMQPProcessor,
        connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
        exchange: [name: to_string(unique_name("ex")), type: :topic, provision: {:create, durable: true}],
        publications: [
          [routing_key: unique_name(:pub1), number_of_performers: 2],
          [routing_key: unique_name(:pub2)]
        ],
        subscriptions: [
          [
            name: unique_name(:sub1),
            topic_or_queue: to_string(unique_name(:queue1)),
            routing_key: unique_name(:sub_rk1),
            provision: {:create, durable: true}
          ]
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)

      pid = start_supervised!({AMQP, opts})
      assert Process.alive?(pid)

      children = Supervisor.which_children(pid)
      specs = Enum.map(children, fn {id, _pid, _type, _mods} -> id end)

      assert Enum.any?(specs, fn id ->
               match?({Ming.Gateway.AMQP.Connection, _}, id) or
                 id == Ming.Gateway.AMQP.Connection
             end)
    end

    test "producer/0 returns the producer module" do
      assert AMQP.producer() == Producer
    end
  end

  describe "provision_infrastructure/1" do
    setup %{amqp_conn: conn, amqp_chan: chan} do
      [amqp_conn: conn, amqp_chan: chan]
    end

    defp passive_exchange_exists(chan, exchange) do
      try do
        Exchange.declare(chan, to_string(exchange), :topic, passive: true)
      catch
        :exit, {:shutdown, {:server_initiated_close, 404, _}} -> {:error, :not_found}
        :exit, {{:shutdown, {:server_initiated_close, 404, _}}, _} -> {:error, :not_found}
        :exit, reason -> {:error, reason}
      end
    end

    defp passive_queue_exists(chan, queue) do
      try do
        Queue.declare(chan, to_string(queue), passive: true)
      catch
        :exit, {:shutdown, {:server_initiated_close, 404, _}} -> {:error, :not_found}
        :exit, {{:shutdown, {:server_initiated_close, 404, _}}, _} -> {:error, :not_found}
        :exit, reason -> {:error, reason}
      end
    end

    test "creates exchange with :create provision", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_create")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert :ok = Exchange.declare(chan, to_string(exchange), :topic, passive: true)
    end

    test "uses plain binary exchange name", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_binary")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: to_string(exchange)
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      # Binary exchange without provision does not create it
      assert {:error, :not_found} = passive_exchange_exists(chan, exchange)
    end

    test "validates existing exchange with :validate provision", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_validate")
      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :validate]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
    end

    test "validating missing exchange returns error", %{amqp_chan: _chan} do
      exchange = unique_name("prov_ex_validate_missing")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :validate]
      ]

      assert {:error, _} = AMQP.provision_infrastructure(opts)
    end

    test ":assume provision skips exchange declaration", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_assume")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert {:error, :not_found} = passive_exchange_exists(chan, exchange)
    end

    test "{:create, opts} applies custom options", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_opts")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert :ok = Exchange.declare(chan, to_string(exchange), :topic, passive: true)
    end

    test "creates dead-letter exchange when configured", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_dlx_main")
      dlx = unique_name("prov_ex_dlx")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}],
        dead_letter_exchange: [name: to_string(dlx), type: :fanout, provision: {:create, durable: true}]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert :ok = Exchange.declare(chan, to_string(dlx), :fanout, passive: true)
    end

    test "creates subscription queue and binding", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_create")
      queue = unique_name("prov_queue_create")
      routing_key = unique_name("prov_rk_create")

      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: {:create, durable: true}
          ]
        ]
      ]

      queue_str = to_string(queue)
      assert :ok = AMQP.provision_infrastructure(opts)
      assert {:ok, %{queue: ^queue_str}} = Queue.declare(chan, queue_str, passive: true)
    end

    test "validates existing subscription queue", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_validate")
      queue = unique_name("prov_queue_validate")
      routing_key = unique_name("prov_rk_validate")

      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)
      assert {:ok, _} = Queue.declare(chan, to_string(queue), durable: true)
      :ok = Queue.bind(chan, to_string(queue), to_string(exchange), routing_key: to_string(routing_key))

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: :validate
          ]
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
    end

    test "validating missing subscription queue returns error", %{amqp_chan: _chan} do
      exchange = unique_name("prov_ex_sub_validate_missing")
      queue = unique_name("prov_queue_validate_missing")
      routing_key = unique_name("prov_rk_validate_missing")

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: :validate
          ]
        ]
      ]

      assert {:error, _} = AMQP.provision_infrastructure(opts)
    end

    test ":assume provision skips queue declaration", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_assume")
      queue = unique_name("prov_queue_assume")
      routing_key = unique_name("prov_rk_assume")

      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: :assume
          ]
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert {:error, :not_found} = passive_queue_exists(chan, queue)
    end

    test "{:create, opts} applies custom queue options", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_opts")
      queue = unique_name("prov_queue_opts")
      routing_key = unique_name("prov_rk_opts")

      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: {:create, durable: true}
          ]
        ]
      ]

      queue_str = to_string(queue)
      assert :ok = AMQP.provision_infrastructure(opts)
      assert {:ok, %{queue: ^queue_str}} = Queue.declare(chan, queue_str, passive: true)
    end

    test "returns error and cleans up on connection failure" do
      opts = [
        connection: [uri: "amqp://guest:guest@localhost:9999"],
        exchange: [name: "unused", type: :topic, provision: {:create, durable: true}]
      ]

      assert {:error, _} = AMQP.provision_infrastructure(opts)
    end
  end

  describe "end-to-end" do
    test "supervisor starts, publishes and consumes a message", %{amqp_chan: chan} do
      exchange = unique_name("e2e_exchange")
      queue = unique_name("e2e_queue")
      routing_key = unique_name("e2e_rk")

      :ok = Exchange.declare(chan, to_string(exchange), :topic, durable: true)
      assert {:ok, _} = Queue.declare(chan, to_string(queue), durable: true)
      :ok = Queue.bind(chan, to_string(queue), to_string(exchange), routing_key: to_string(routing_key))

      name = unique_name(:e2e_gateway)

      opts = [
        name: name,
        command_processor: TestAMQPProcessor,
        connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
        exchange: [name: to_string(exchange), type: :topic, provision: :assume],
        publications: [[routing_key: routing_key]],
        subscriptions: [
          [
            name: unique_name(:e2e_sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: :assume
          ]
        ]
      ]

      pid = start_supervised!({AMQP, opts})
      assert Process.alive?(pid)

      message = %Message{
        id: "e2e-1",
        payload: "end to end",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [
        adapter: AMQP,
        name: name,
        exchange: [name: to_string(exchange), type: :topic]
      ]

      publication = [routing_key: routing_key]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      assert_receive {:consumed, %Message{payload: "end to end"} = consumed, _opts}, 3_000
      assert consumed.id == "e2e-1"

      # Give consumer time to ack, then assert queue is empty
      Process.sleep(200)
      assert {:empty, _} = Basic.get(chan, to_string(queue))
    end
  end
end
