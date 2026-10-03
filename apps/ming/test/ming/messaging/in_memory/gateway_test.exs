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
    assert Queue.poll(:in_memory_gateway_test_key, 10) == [:hello]
    assert Queue.poll(:in_memory_gateway_test_key, 10) == []
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
    assert Queue.poll("in_memory_gateway_test.string", 10) == [:hello]
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
end
