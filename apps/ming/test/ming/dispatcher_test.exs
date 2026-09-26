defmodule Ming.DispatcherTest do
  use ExUnit.Case, async: true

  alias Ming.Context

  defmodule EchoHandler do
    @behaviour Ming.Handler

    def handle(request, context) do
      {:ok,
       %{
         request: request,
         trace: Enum.reverse(Map.get(context.assigns, :trace, [])),
         routing_key: context.routing_key,
         correlation_id: context.correlation_id,
         metadata: context.metadata
       }}
    end
  end

  defmodule SecondHandler do
    @behaviour Ming.Handler
    def handle(_request, _context), do: :ok
  end

  defmodule SlowHandler do
    @behaviour Ming.Handler
    def handle(_request, _context) do
      Process.sleep(200)
      :ok
    end
  end

  defmodule TraceMiddleware do
    @behaviour Ming.Middleware

    def execute(context, name, next) do
      trace = [name | Map.get(context.assigns, :trace, [])]
      next.(Context.assign(context, :trace, trace))
    end
  end

  defmodule ReverseStrategy do
    @behaviour Ming.ExecutionStrategy

    def execute(pipelines, context, _args) do
      pipelines |> Enum.reverse() |> Enum.map(&Ming.Pipeline.run(&1, context))
    end
  end

  defmodule MyCommand do
    defstruct []
  end

  defmodule SampleRouter do
    use Ming.Router

    middleware(TraceMiddleware, args: :router)

    routing_key("router.key", handler: EchoHandler)
  end

  defmodule SampleDispatcher do
    use Ming.Dispatcher

    middleware(TraceMiddleware, args: :dispatcher)

    router(SampleRouter)

    routing_key("one",
      handler: EchoHandler,
      middlewares: [{TraceMiddleware, args: :key, order: 5}]
    )

    routing_key("many", handlers: [EchoHandler, SecondHandler])
    routing_key("slow", handler: SlowHandler)
    routing_key(MyCommand, handler: EchoHandler)
  end

  defmodule DefaultsDispatcher do
    use Ming.Dispatcher, timeout: 30, metadata: %{origin: :defaults}

    routing_key("one", handler: EchoHandler)
    routing_key("slow", handler: SlowHandler)
    routing_key(:slow_command, handler: SlowHandler)
  end

  describe "send/2" do
    test "returns the handler response" do
      assert {:ok, %{request: :hello}} = SampleDispatcher.send(:hello, routing_key: "one")
    end

    test "infers the routing key from the request struct" do
      assert {:ok, %{routing_key: MyCommand}} = SampleDispatcher.send(struct(MyCommand))
    end

    test "returns {:error, :unregistered_routing_key} for unknown keys" do
      assert SampleDispatcher.send(:hello, routing_key: "unknown") ==
               {:error, :unregistered_routing_key}
    end

    test "returns {:error, :more_than_one_handler_found} when the key has many handlers" do
      assert SampleDispatcher.send(:hello, routing_key: "many") ==
               {:error, :more_than_one_handler_found}
    end

    test "runs dispatcher-level middleware around key-level middleware, ordered by :order" do
      assert {:ok, %{trace: [:dispatcher, :key]}} =
               SampleDispatcher.send(:hello, routing_key: "one")
    end

    test "accepts extra middleware per dispatch" do
      assert {:ok, %{trace: [:dispatcher, :key, :extra]}} =
               SampleDispatcher.send(:hello,
                 routing_key: "one",
                 middlewares: [{TraceMiddleware, args: :extra, order: 10}]
               )
    end

    test "sets context fields from opts" do
      assert {:ok, %{correlation_id: "corr", metadata: %{tenant: "acme"}}} =
               SampleDispatcher.send(:hello,
                 routing_key: "one",
                 id: "id",
                 correlation_id: "corr",
                 metadata: %{tenant: "acme"}
               )
    end

    test "times out with {:error, :timeout}" do
      assert SampleDispatcher.send(:hello, routing_key: "slow", timeout: 20) ==
               {:error, :timeout}
    end

    test "accepts a bare timeout as second argument" do
      assert DefaultsDispatcher.send(:slow_command, 20) == {:error, :timeout}
    end
  end

  describe "publish/2" do
    test "returns one response per handler" do
      assert [{:ok, %{request: :evt}}, :ok] =
               SampleDispatcher.publish(:evt, routing_key: "many")
    end

    test "runs pipelines in parallel with the :parallel strategy" do
      assert [{:ok, _}, :ok] =
               SampleDispatcher.publish(:evt, routing_key: "many", execution_strategy: :parallel)
    end

    test "accepts a custom strategy module" do
      assert [:ok, {:ok, _}] =
               SampleDispatcher.publish(:evt,
                 routing_key: "many",
                 execution_strategy: ReverseStrategy
               )
    end

    test "returns {:error, :unregistered_routing_key} for unknown keys" do
      assert SampleDispatcher.publish(:evt, routing_key: "unknown") ==
               {:error, :unregistered_routing_key}
    end
  end

  describe "router/1" do
    test "imports routing keys and applies dispatcher-level middleware" do
      assert {:ok, %{trace: [:dispatcher, :router]}} =
               SampleDispatcher.send(:hello, routing_key: "router.key")
    end
  end

  describe "use defaults" do
    test "timeout and metadata from use opts apply to every dispatch" do
      assert {:error, :timeout} = DefaultsDispatcher.send(:hello, routing_key: "slow")

      assert {:ok, %{metadata: %{origin: :defaults}}} =
               DefaultsDispatcher.send(:hello, routing_key: "one")
    end

    test "dispatch opts override use defaults" do
      assert {:ok, %{metadata: %{tenant: "acme"}}} =
               DefaultsDispatcher.send(:hello, routing_key: "one", metadata: %{tenant: "acme"})
    end
  end

  defmodule T1 do
    def transform(message), do: message
  end

  defmodule T2 do
    def transform(message), do: message
  end

  defmodule T3 do
    def transform(message), do: message
  end

  defmodule GatewayDispatcher do
    use Ming.Dispatcher, timeout: 1_234

    transformer(T2, order: 5)
    transformer(T3, order: 10)

    gateway(:kafka, FakeAdapter,
      connection: [endpoints: [{"localhost", 9092}]],
      publications: [
        %{routing_key: :created, transformers: [{T1, [args: :pub, order: 2]}]}
      ],
      subscriptions: [
        %{name: :orders, routing_key: :created, batch_processing: :parallel}
      ]
    )
  end

  describe "gateway/3" do
    test "stores the adapter and injects gateway name and mapper defaults" do
      config = GatewayDispatcher.__gateways__()[:kafka]

      assert config.adapter == FakeAdapter
      assert config.connection == [endpoints: [{"localhost", 9092}]]

      [publication] = config.publications
      assert publication.gateway_name == :kafka
      assert publication.mapper == :json

      [subscription] = config.subscriptions
      assert subscription.gateway_name == :kafka
      assert subscription.mapper == :json
    end

    test "keeps per-subscription batch_processing over the dispatcher default" do
      [subscription] = GatewayDispatcher.__gateways__()[:kafka].subscriptions

      assert subscription.batch_processing == :parallel
    end
  end

  describe "transformer/2" do
    test "merges dispatcher transformers into publications and subscriptions by :order" do
      [publication] = GatewayDispatcher.__gateways__()[:kafka].publications

      assert publication.transformers == [
               {T1, [args: :pub, order: 2]},
               {T2, [order: 5]},
               {T3, [order: 10]}
             ]

      [subscription] = GatewayDispatcher.__gateways__()[:kafka].subscriptions

      assert subscription.transformers == [{T2, [order: 5]}, {T3, [order: 10]}]
    end
  end

  describe "config/0" do
    setup do
      on_exit(fn -> Application.delete_env(:ming, GatewayDispatcher) end)
    end

    test "returns the compile-time defaults" do
      config = GatewayDispatcher.config()

      assert config[:mapper] == :json
      assert config[:timeout] == 1_234
      assert config[:gateways][:kafka].adapter == FakeAdapter
    end

    test "merges overrides from the application environment" do
      Application.put_env(:ming, GatewayDispatcher,
        timeout: 9_000,
        gateways: [kafka: [publications: [[routing_key: :created, topic_or_queue: "orders.v2"]]]]
      )

      config = GatewayDispatcher.config()

      assert config[:timeout] == 9_000

      [publication] = config[:gateways][:kafka].publications
      assert publication.topic_or_queue == "orders.v2"
      assert publication.gateway_name == :kafka
    end
  end
end
