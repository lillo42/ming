defmodule Ming.RouterTest do
  use ExUnit.Case

  defmodule MyCommand do
    defstruct [:value]
  end

  defmodule MyEvent do
    defstruct [:value]
  end

  defmodule MyHandler do
    def handle(%MyCommand{}, _context), do: :ok
    def handle(%MyEvent{}, _context), do: :ok
    def handle(%{payload: _}, _context), do: :ok
  end

  defmodule FlakyHandler do
    @moduledoc """
    Fails twice before returning `:ok`, counting attempts in the agent
    carried by the command value.
    """

    def handle(%MyCommand{value: counter}, _context) when is_pid(counter) do
      attempt = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)

      if attempt > 2 do
        :ok
      else
        {:error, :failed}
      end
    end
  end

  defmodule MyRouter do
    use Ming.Router

    register(MyCommand, handler: MyHandler)
    register(MyEvent, handler: MyHandler)
    register(:my_atom_key, handler: MyHandler)

    register(:retry_key,
      handler: FlakyHandler,
      retry: [max_retries: 3, base_delay: 1, backoff_type: :fixed]
    )
  end

  describe "send/3" do
    test "routes command to handler" do
      assert MyRouter.send(MyCommand, %MyCommand{value: 1}) == :ok
    end

    test "routes command to handler when routing key is an atom" do
      assert MyRouter.send(:my_atom_key, %{payload: 1}) == :ok
    end

    test "returns unregistered for unknown routing key" do
      assert MyRouter.send(UnknownKey, %MyCommand{value: 1}) == {:error, :unregistered_command}
    end

    test "retries the handler according to the registered retry option" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      assert MyRouter.send(:retry_key, %MyCommand{value: counter}) == :ok
      assert Agent.get(counter, & &1) == 3
    end

    test "a per-call retry option overrides the registered one" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      assert MyRouter.send(:retry_key, %MyCommand{value: counter}, retry: 0) ==
               {:error, :failed}

      assert Agent.get(counter, & &1) == 1
    end
  end

  describe "publish/3" do
    test "routes event to handler" do
      assert MyRouter.publish(MyEvent, %MyEvent{value: 2}) == :ok
    end

    test "routes event to handler when routing key is an atom" do
      assert MyRouter.publish(:my_atom_key, %{payload: 2}) == :ok
    end

    test "returns unregistered for unknown routing key" do
      assert MyRouter.publish(UnknownKey, %MyEvent{value: 1}) == {:error, :unregistered_command}
    end
  end
end
