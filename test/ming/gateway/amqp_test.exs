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

  setup %{amqp_conn: conn, amqp_chan: chan} do
    Application.put_env(:ming, :amqp_test_target_pid, self())

    on_exit(fn ->
      Application.delete_env(:ming, :amqp_test_target_pid)
    end)

    [amqp_conn: conn, amqp_chan: chan]
  end

  defp declare_exchange(chan, exchange, opts \\ [durable: true]) do
    exchange_str = to_string(exchange)
    :ok = Exchange.declare(chan, exchange_str, :topic, opts)

    on_exit(fn ->
      try do
        Exchange.delete(chan, exchange_str)
      catch
        _, _ -> :ok
      end
    end)
  end

  defp declare_queue(chan, queue, exchange, routing_key) do
    queue_str = to_string(queue)
    exchange_str = to_string(exchange)
    assert {:ok, _} = Queue.declare(chan, queue_str, durable: true)

    :ok =
      Queue.bind(chan, queue_str, exchange_str, routing_key: to_string(routing_key))

    on_exit(fn ->
      try do
        Queue.delete(chan, queue_str)
      catch
        _, _ -> :ok
      end
    end)
  end

  defp delete_on_exit(chan, exchange, queue \\ nil) do
    on_exit(fn ->
      try do
        if queue, do: Queue.delete(chan, to_string(queue))
        Exchange.delete(chan, to_string(exchange))
      catch
        _, _ -> :ok
      end
    end)
  end

  describe "start_link/1 and init/1" do
    test "starts supervisor with connection, publishers, consumers and pools", %{
      amqp_chan: chan
    } do
      name = unique_name(:amqp_gateway)
      exchange = unique_name("ex")
      queue = unique_name("queue1")

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, unique_name(:sub_rk1))

      opts = [
        name: name,
        command_processor: TestAMQPProcessor,
        connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
        exchange: [
          name: to_string(exchange),
          type: :topic,
          provision: {:create, durable: true}
        ],
        publications: [
          [routing_key: unique_name(:pub1), number_of_performers: 2],
          [routing_key: unique_name(:pub2)]
        ],
        subscriptions: [
          [
            name: unique_name(:sub1),
            topic_or_queue: to_string(queue),
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

      delete_on_exit(chan, exchange)

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
      declare_exchange(chan, exchange)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: :validate]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
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

      delete_on_exit(chan, exchange)

      assert :ok = AMQP.provision_infrastructure(opts)
      assert :ok = Exchange.declare(chan, to_string(exchange), :topic, passive: true)
    end

    test "creates dead-letter exchange when configured", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_dlx_main")
      dlx = unique_name("prov_ex_dlx")

      delete_on_exit(chan, exchange)
      delete_on_exit(chan, dlx)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}],
        dead_letter_exchange: [
          name: to_string(dlx),
          type: :fanout,
          provision: {:create, durable: true}
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)
      assert :ok = Exchange.declare(chan, to_string(dlx), :fanout, passive: true)
    end

    test "creates subscription queue and binding", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_create")
      queue = unique_name("prov_queue_create")
      routing_key = unique_name("prov_rk_create")

      declare_exchange(chan, exchange)
      delete_on_exit(chan, exchange, queue)

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

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, routing_key)

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

    test "validating missing subscription queue returns error", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_sub_validate_missing")
      queue = unique_name("prov_queue_validate_missing")
      routing_key = unique_name("prov_rk_validate_missing")

      delete_on_exit(chan, exchange)

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

      declare_exchange(chan, exchange)

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

      declare_exchange(chan, exchange)
      delete_on_exit(chan, exchange, queue)

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

    test "{:create, opts} passes queue arguments to the broker", %{amqp_chan: chan} do
      exchange = unique_name("prov_ex_args")
      queue = unique_name("prov_queue_args")
      routing_key = unique_name("prov_rk_args")

      delete_on_exit(chan, exchange, queue)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: {:create, durable: true, arguments: [{"x-max-length", :long, 1}]}
          ]
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "first")
      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "second")
      Process.sleep(100)

      # x-max-length: 1 drops the oldest message (default drop-head overflow)
      assert {:ok, "second", _meta} = Basic.get(chan, to_string(queue), no_ack: true)
      assert {:empty, _} = Basic.get(chan, to_string(queue), no_ack: true)
    end

    test "provisioned binding routes messages with the subscription routing key", %{
      amqp_chan: chan
    } do
      exchange = unique_name("prov_ex_bind_routes")
      queue = unique_name("prov_queue_bind_routes")
      routing_key = unique_name("prov_rk_bind_routes")

      delete_on_exit(chan, exchange, queue)

      opts = [
        connection: [uri: rabbit_uri()],
        exchange: [name: to_string(exchange), type: :topic, provision: {:create, durable: true}],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: to_string(queue),
            routing_key: routing_key,
            provision: {:create, durable: true}
          ]
        ]
      ]

      assert :ok = AMQP.provision_infrastructure(opts)

      :ok = Basic.publish(chan, to_string(exchange), to_string(routing_key), "routed")
      :ok = Basic.publish(chan, to_string(exchange), "other.key", "not routed")
      Process.sleep(100)

      assert {:ok, "routed", _meta} = Basic.get(chan, to_string(queue), no_ack: true)
      assert {:empty, _} = Basic.get(chan, to_string(queue), no_ack: true)
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
    defp boot_e2e_processor(publications, subscriptions, exchange) do
      Application.put_env(:ming, :amqp_e2e_pid, self())

      Application.put_env(:ming, AMQPE2EProcessor,
        gateways: [
          [
            adapter: AMQP,
            name: unique_name(:e2e_cp_gateway),
            connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
            exchange: [name: to_string(exchange), type: :topic, provision: :assume],
            publications: publications,
            subscriptions: subscriptions
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :amqp_e2e_pid)
        Application.delete_env(:ming, :amqp_e2e_response)
        Application.delete_env(:ming, AMQPE2EProcessor)
      end)

      start_supervised!(AMQPE2EProcessor)
    end

    defp eventually(fun, attempts \\ 50)
    defp eventually(_fun, 0), do: false

    defp eventually(fun, attempts) do
      if fun.() do
        true
      else
        Process.sleep(100)
        eventually(fun, attempts - 1)
      end
    end

    defp get_with_retry(chan, queue, attempts \\ 50)

    defp get_with_retry(chan, queue, 0), do: Basic.get(chan, to_string(queue), no_ack: true)

    defp get_with_retry(chan, queue, attempts) do
      case Basic.get(chan, to_string(queue), no_ack: true) do
        {:empty, _} ->
          Process.sleep(100)
          get_with_retry(chan, queue, attempts - 1)

        {:ok, payload, meta} ->
          {:ok, payload, meta}
      end
    end

    test "supervisor starts, publishes and consumes a message", %{amqp_chan: chan} do
      exchange = unique_name("e2e_exchange")
      queue = unique_name("e2e_queue")
      routing_key = unique_name("e2e_rk")

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, routing_key)

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

    test "post/2 round-trips through a real command processor", %{amqp_chan: chan} do
      exchange = unique_name("e2e_cp_exchange")
      queue = unique_name("e2e_cp_queue")
      routing_key = :e2e_shipped

      Application.put_env(:ming, :amqp_e2e_pid, self())

      Application.put_env(:ming, AMQPE2EProcessor,
        gateways: [
          [
            adapter: AMQP,
            name: unique_name(:e2e_cp_gateway),
            connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
            exchange: [
              name: to_string(exchange),
              type: :topic,
              provision: {:create, durable: true}
            ],
            publications: [[routing_key: routing_key]],
            subscriptions: [
              [
                name: unique_name(:e2e_cp_sub),
                topic_or_queue: to_string(queue),
                routing_key: routing_key,
                provision: {:create, durable: true}
              ]
            ]
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :amqp_e2e_pid)
        Application.delete_env(:ming, AMQPE2EProcessor)

        try do
          Queue.delete(chan, to_string(queue))
          Exchange.delete(chan, to_string(exchange))
        catch
          _, _ -> :ok
        end
      end)

      pid = start_supervised!(AMQPE2EProcessor)
      assert Process.alive?(pid)

      assert :ok = AMQPE2EProcessor.post(%{"id" => 1, "tracking_code" => "BR123"}, routing_key)

      assert_receive {:handled, :e2e_shipped, request, metadata, _assigns}, 5_000
      assert request == %{"id" => 1, "tracking_code" => "BR123"}
      assert metadata[:routing_key] == routing_key

      # Give consumer time to ack, then assert queue is empty
      Process.sleep(200)
      assert {:empty, _} = Basic.get(chan, to_string(queue))
    end

    test "concurrent posts all succeed", %{amqp_chan: chan} do
      exchange = unique_name("e2e_conc_exchange")
      queue = unique_name("e2e_conc_queue")

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, :e2e_shipped)

      boot_e2e_processor(
        [[routing_key: :e2e_shipped]],
        [
          [
            name: unique_name(:e2e_conc_sub),
            topic_or_queue: to_string(queue),
            routing_key: :e2e_shipped,
            provision: :assume
          ]
        ],
        exchange
      )

      results =
        1..20
        |> Task.async_stream(fn i -> AMQPE2EProcessor.post(%{"i" => i}, :e2e_shipped) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &(&1 == :ok))
    end

    test "rejects poison payloads without crashing the consumer", %{amqp_chan: chan} do
      exchange = unique_name("e2e_poison_exchange")
      queue = unique_name("e2e_poison_queue")

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, :e2e_shipped)

      boot_e2e_processor(
        [[routing_key: :e2e_shipped]],
        [
          [
            name: unique_name(:e2e_poison_sub),
            topic_or_queue: to_string(queue),
            routing_key: :e2e_shipped,
            provision: :assume
          ]
        ],
        exchange
      )

      :ok = Basic.publish(chan, to_string(exchange), "e2e_shipped", "not json{{")

      assert eventually(fn -> match?({:empty, _}, Basic.get(chan, to_string(queue))) end)

      refute_receive {:handled, _, _, _, _}, 500

      assert :ok = AMQPE2EProcessor.post(%{"id" => 2}, :e2e_shipped)
      assert_receive {:handled, :e2e_shipped, %{"id" => 2}, _metadata, _assigns}, 5_000
    end

    test "propagates trace context through produce and consume", %{amqp_chan: chan} do
      exchange = unique_name("e2e_trace_exchange")
      queue = unique_name("e2e_trace_queue")

      declare_exchange(chan, exchange)
      declare_queue(chan, queue, exchange, :e2e_shipped)

      boot_e2e_processor([[routing_key: :e2e_shipped]], [], exchange)

      trace_parent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      assert :ok =
               AMQPE2EProcessor.post(%{"id" => 3},
                 routing_key: :e2e_shipped,
                 metadata: %{trace_parent: trace_parent}
               )

      assert {:ok, payload, meta} = get_with_retry(chan, queue)
      assert JSON.decode!(payload) == %{"id" => 3}

      headers = Map.new(meta.headers || [], fn {key, _type, value} -> {key, value} end)
      assert headers["cloudEvents:traceparent"] == trace_parent
    end

    defp boot_dlx_processor(chan) do
      exchange = unique_name("e2e_dlx_exchange")
      dlx = unique_name("e2e_dlx_dlx")
      queue = unique_name("e2e_dlx_queue")
      dlq = unique_name("e2e_dlx_dlq")

      Application.put_env(:ming, :amqp_e2e_pid, self())

      Application.put_env(:ming, AMQPE2EProcessor,
        gateways: [
          [
            adapter: AMQP,
            name: unique_name(:e2e_cp_gateway),
            connection: [uri: rabbit_uri(), retry: [max_retries: 1, base_delay: 10]],
            exchange: [
              name: to_string(exchange),
              type: :topic,
              provision: {:create, durable: true}
            ],
            dead_letter_exchange: [
              name: to_string(dlx),
              type: :topic,
              provision: {:create, durable: true}
            ],
            publications: [[routing_key: :e2e_shipped]],
            subscriptions: [
              [
                name: unique_name(:e2e_dlx_sub),
                topic_or_queue: to_string(queue),
                routing_key: :e2e_shipped,
                dead_letter: to_string(dlq),
                provision: {:create, durable: true}
              ]
            ]
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :amqp_e2e_pid)
        Application.delete_env(:ming, :amqp_e2e_response)
        Application.delete_env(:ming, AMQPE2EProcessor)

        try do
          Queue.delete(chan, to_string(queue))
          Queue.delete(chan, to_string(dlq))
          Exchange.delete(chan, to_string(exchange))
          Exchange.delete(chan, to_string(dlx))
        catch
          _, _ -> :ok
        end
      end)

      start_supervised!(AMQPE2EProcessor)

      %{exchange: exchange, dlx: dlx, queue: queue, dlq: dlq}
    end

    test "rejected messages are dead-lettered by the broker", %{amqp_chan: chan} do
      %{dlq: dlq} = boot_dlx_processor(chan)

      Application.put_env(:ming, :amqp_e2e_response, :reject)

      assert :ok = AMQPE2EProcessor.post(%{"id" => 5}, :e2e_shipped)

      assert_receive {:handled, :e2e_shipped, %{"id" => 5}, _metadata, _assigns}, 5_000

      assert {:ok, payload, _meta} = get_with_retry(chan, dlq)
      assert JSON.decode!(payload) == %{"id" => 5}
    end

    test "unacceptable messages are dead-lettered by the broker", %{amqp_chan: chan} do
      %{exchange: exchange, dlq: dlq} = boot_dlx_processor(chan)

      :ok = Basic.publish(chan, to_string(exchange), "e2e_shipped", "not json{{")

      assert {:ok, "not json{{", _meta} = get_with_retry(chan, dlq)
      refute_receive {:handled, _, _, _, _}, 500
    end
  end
end

defmodule AMQPE2EHandler do
  @moduledoc false
  @behaviour Ming.Handler

  # Sends {:handled, routing_key, request, metadata, assigns} to the pid in
  # :amqp_e2e_pid. The response for :e2e_shipped is read from
  # :amqp_e2e_response (default :ok); other routing keys always return :ok.
  def handle(request, context) do
    send(
      Application.get_env(:ming, :amqp_e2e_pid),
      {:handled, context.routing_key, request, context.metadata, context.assigns}
    )

    case context.routing_key do
      :e2e_shipped -> Application.get_env(:ming, :amqp_e2e_response, :ok)
      _other -> :ok
    end
  end
end

defmodule AMQPE2ERouter do
  @moduledoc false
  use Ming.Router

  register(:e2e_shipped, handler: AMQPE2EHandler)
end

defmodule AMQPE2EProcessor do
  @moduledoc false
  use Ming.CommandProcessor, otp_app: :ming

  router(AMQPE2ERouter)
end
