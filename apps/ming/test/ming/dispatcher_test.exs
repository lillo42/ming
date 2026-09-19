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
end
