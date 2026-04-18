defmodule Ming.CommandProcessorTest do
  use ExUnit.Case

  describe "send/2 through command processor" do
    test "dispatches registered command" do
      resp = Ming.CustomCommandProcessor.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "returns unregistered for unknown command" do
      resp = Ming.CustomCommandProcessor.send(%Ming.ExampleCommand2{})
      assert resp == {:error, :unregistered_command}
    end
  end

  describe "publish/2 through command processor" do
    test "publishes registered event" do
      resp = Ming.CustomCommandProcessor.publish(%Ming.ExampleEvent1{})
      assert resp == :ok
    end

    test "returns ok for unregistered event" do
      resp = Ming.CustomCommandProcessor.publish(%Ming.ExampleCommand2{})
      assert resp == :ok
    end
  end

  describe "query/2 through command processor" do
    test "queries registered query" do
      resp = Ming.CustomCommandProcessor.query(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "returns unregistered for unknown query" do
      resp = Ming.CustomCommandProcessor.query(%Ming.ExampleCommand2{})
      assert resp == {:error, :unregistered_query}
    end
  end
end
