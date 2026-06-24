defmodule Ming.CommandProcessorTest do
  use ExUnit.Case

  defmodule CommandOne do
    defstruct [:val]
  end

  defmodule CommandTwo do
    defstruct [:val]
  end

  defmodule EventOne do
    defstruct [:val]
  end

  defmodule EventTwo do
    defstruct [:val]
  end

  defmodule MyHandler do
    def handle(%CommandOne{val: val}, _ctx), do: {:ok, val}
    def handle(%CommandTwo{}, _ctx), do: :ok
    def handle(%EventOne{val: val}, _ctx), do: {:ok, val}
    def handle(%EventTwo{}, _ctx), do: :ok
    def handle(%{payload: val}, _ctx), do: {:ok, val}
  end

  defmodule RouterOne do
    use Ming.Router
    register(CommandOne, handler: MyHandler)
    register(EventOne, handler: MyHandler)
    register(:atom_key_one, handler: MyHandler)
  end

  defmodule RouterTwo do
    use Ming.Router
    register(CommandTwo, handler: MyHandler)
    register(EventTwo, handler: MyHandler)
    # Same event handled in both routers
    register(EventOne, handler: MyHandler)
    register(:atom_key_two, handler: MyHandler)
  end

  defmodule MyProcessor do
    use Ming.CommandProcessor

    router(RouterOne)
    router(RouterTwo)
  end

  describe "send/2" do
    test "routes command to the correct router" do
      assert {:ok, 42} = MyProcessor.send(%CommandOne{val: 42})
      assert :ok = MyProcessor.send(%CommandTwo{})
    end

    test "routes command correctly when using an atom routing key" do
      assert {:ok, 10} = MyProcessor.send(%{payload: 10}, :atom_key_one)
      assert {:ok, 20} = MyProcessor.send(%{payload: 20}, :atom_key_two)
    end

    test "returns unregistered for unknown command" do
      assert {:error, :unregistered_command} = MyProcessor.send(%{__struct__: UnknownCommand})
    end

    test "returns more_than_one_handler_found when routers conflict" do
      # Note: this is actually an Event handled as a Command but if we registered the same
      # command twice it would fail similarly. We can just test send with EventOne which has two routers.
      assert {:error, :more_than_one_handler_found} = MyProcessor.send(%EventOne{})
    end
  end

  describe "publish/2" do
    test "publishes event to a single router" do
      assert :ok = MyProcessor.publish(%EventTwo{})
    end

    test "publishes event correctly when using an atom routing key" do
      assert {:ok, 30} = MyProcessor.publish(%{payload: 30}, :atom_key_one)
      assert {:ok, 40} = MyProcessor.publish(%{payload: 40}, :atom_key_two)
    end

    test "publishes event sequentially to multiple routers by default" do
      # Both RouterOne and RouterTwo handle EventOne.
      assert [{:ok, 100}, {:ok, 100}] = MyProcessor.publish(%EventOne{val: 100})
    end

    test "publishes event in parallel" do
      results = MyProcessor.publish(%EventOne{val: 99}, execute_mode: :parallel)
      assert length(results) == 2
      assert {:ok, 99} in results
    end
  end
end
