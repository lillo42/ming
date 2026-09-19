defmodule Ming.RouterTest do
  use ExUnit.Case, async: true

  defmodule HandlerA do
    @behaviour Ming.Handler
    def handle(request, _context), do: {:ok, request}
  end

  defmodule HandlerB do
    @behaviour Ming.Handler
    def handle(_request, _context), do: :ok
  end

  defmodule SampleMiddleware do
    @behaviour Ming.Middleware
    def execute(context, _args, next), do: next.(context)
  end

  defmodule SampleRouter do
    use Ming.Router

    middleware(SampleMiddleware)

    routing_key("one", handler: HandlerA)
    routing_key(["two", "three"], handler: HandlerB)
    routing_key("many", handlers: [HandlerA, HandlerB])
    routing_key("bare")
  end

  test "declares one entry per key/handler pair" do
    keys = SampleRouter.__routing_keys__()

    assert {"one", one_opts} = List.keyfind(keys, "one", 0)
    assert {"two", _} = List.keyfind(keys, "two", 0)
    assert {"three", _} = List.keyfind(keys, "three", 0)
    assert {"bare", bare_opts} = List.keyfind(keys, "bare", 0)

    assert length(for {"many", _} <- keys, do: true) == 2

    assert List.last(one_opts[:middlewares]) ==
             {Ming.Middleware.HandlerRunner, [args: HandlerA, order: 10_000]}

    assert bare_opts[:middlewares] == [{SampleMiddleware, []}]
  end

  test "router-level middleware wraps every pipeline" do
    for {key, opts} <- SampleRouter.__routing_keys__() do
      assert {SampleMiddleware, []} in opts[:middlewares],
             "expected router middleware in pipeline for #{key}"
    end
  end

  test "keeps default opts" do
    {"one", opts} = List.keyfind(SampleRouter.__routing_keys__(), "one", 0)
    assert opts[:timeout] == :infinity
    assert opts[:metadata] == %{}
  end
end
