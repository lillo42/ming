defmodule Ming.CompositeRouterTest do
  use ExUnit.Case

  doctest Ming.CompositeRouter

  describe "send/2" do
    test "a handler returning []" do
      resp = Ming.SimpleComposeRouter.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "error multi register for same command" do
      resp = Ming.MultiComposeRouter.send(%Ming.ExampleCommand1{})
      assert resp == {:error, :more_than_one_handler_found}
    end

    test "unregistered command" do
      resp = Ming.SimpleComposeRouter.send(%Ming.ExampleCommand2{})
      assert resp == {:error, :unregistered_command}
    end
  end

  describe "publish/2" do
    test "a handler returning ok" do
      resp = Ming.SimpleComposeRouter.publish(%Ming.ExampleEvent1{})
      assert resp == :ok
    end

    test "error multi register for same command" do
      resp = Ming.MultiComposeRouter.publish(%Ming.ExampleEvent1{})
      assert resp == :ok
    end

    test "unregistered command" do
      resp = Ming.SimpleComposeRouter.publish(%Ming.ExampleCommand2{})
      assert resp == :ok
    end
  end
end
