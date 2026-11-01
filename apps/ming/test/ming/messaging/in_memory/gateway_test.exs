defmodule Ming.Messaging.InMemory.GatewayTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.InMemory.Gateway
  alias Ming.Messaging.InMemory.Queue

  test "creates one queue per distinct :create entry" do
    start_supervised!(
      {Gateway,
       %{
         name: :in_memory_gateway_test_shared,
         publications: [%{routing_key: :in_memory_gateway_test_key}],
         subscriptions: [%{name: :sub, routing_key: :in_memory_gateway_test_key}]
       }}
    )

    Queue.push(:in_memory_gateway_test_key, :hello)
    assert Queue.take(:in_memory_gateway_test_key, 10) == [:hello]
    assert Queue.take(:in_memory_gateway_test_key, 10) == []
  end

  test "resolves the queue from the :queue option over the routing key" do
    start_supervised!(
      {Gateway,
       %{
         name: :in_memory_gateway_test_explicit,
         publications: [
           %{routing_key: :in_memory_gateway_test_rk, queue: :in_memory_gateway_test_q}
         ]
       }}
    )

    assert Process.whereis(:in_memory_gateway_test_q)
    refute Process.whereis(:in_memory_gateway_test_rk)
  end

  test "supports string queue names" do
    start_supervised!(
      {Gateway,
       %{
         name: :in_memory_gateway_test_string,
         publications: [%{routing_key: "in_memory_gateway_test.string"}]
       }}
    )

    Queue.push("in_memory_gateway_test.string", :hello)
    assert Queue.take("in_memory_gateway_test.string", 10) == [:hello]
  end

  test "starts no queue for :assume entries" do
    start_supervised!(
      {Gateway,
       %{
         name: :in_memory_gateway_test_assume,
         publications: [%{routing_key: :in_memory_gateway_test_assumed, provisioner: :assume}]
       }}
    )

    refute Process.whereis(:in_memory_gateway_test_assumed)
  end

  test "fails to start when a :validate entry has no queue created" do
    assert {:error, {:queue_not_found, :in_memory_gateway_test_missing}} =
             Gateway.start_link(%{
               name: :in_memory_gateway_test_invalid,
               publications: [
                 %{routing_key: :in_memory_gateway_test_missing, provisioner: :validate}
               ]
             })
  end

  test "starts when a :validate entry matches a :create entry" do
    start_supervised!(
      {Gateway,
       %{
         name: :in_memory_gateway_test_valid,
         publications: [%{routing_key: :in_memory_gateway_test_created}],
         subscriptions: [
           %{
             name: :sub,
             routing_key: :in_memory_gateway_test_created,
             provisioner: :validate
           }
         ]
       }}
    )

    assert Process.whereis(:in_memory_gateway_test_created)
  end

  test "raises when an entry has neither :queue nor :routing_key" do
    assert_raise ArgumentError, ~r/without :queue or :routing_key/, fn ->
      Gateway.start_link(%{
        name: :in_memory_gateway_test_no_key,
        publications: [%{name: :broken}]
      })
    end
  end

  test "raises on an empty queue name" do
    assert_raise ArgumentError, ~r/empty queue name/, fn ->
      Gateway.start_link(%{
        name: :in_memory_gateway_test_empty_name,
        publications: [%{queue: ""}]
      })
    end
  end

  test "raises on a non-positive :buffer_size" do
    for size <- [0, -1, 1.5, "10"] do
      assert_raise ArgumentError, ~r/:buffer_size/, fn ->
        Gateway.start_link(%{
          name: :in_memory_gateway_test_bad_buffer,
          subscriptions: [%{name: :sub, routing_key: :key, buffer_size: size}]
        })
      end
    end
  end
end
