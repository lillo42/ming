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

  defmodule MyRouter do
    use Ming.Router

    register(MyCommand, handler: MyHandler)
    register(MyEvent, handler: MyHandler)
    register(:my_atom_key, handler: MyHandler)
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
