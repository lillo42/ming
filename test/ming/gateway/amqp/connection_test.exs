defmodule Ming.Gateway.AMQP.ConnectionTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.AMQP.Connection` against a live broker.
  """

  use Ming.Gateway.AMQP.Case

  alias AMQP.Connection
  alias Ming.Gateway.AMQP.Connection, as: AMQPConnection

  @moduletag :rabbitmq

  describe "start_link/1" do
    test "connects via URI and returns {:ok, pid}", %{amqp_conn: real_conn} do
      name = unique_name(:connection)

      opts = [
        name: name,
        connection: [uri: rabbit_uri()],
        retry: [max_retries: 1, base_delay: 10]
      ]

      pid = start_supervised!({AMQPConnection, opts})
      assert Process.alive?(pid)

      conn = AMQPConnection.get_connection!(name)
      assert is_struct(conn, Connection)
      assert Process.alive?(conn.pid)
      assert conn.pid != real_conn.pid
    end

    test "connects via connection options", %{amqp_chan: _chan} do
      name = unique_name(:connection)

      opts = [
        name: name,
        connection: [
          host: "localhost",
          port: 5672,
          username: "guest",
          password: "guest",
          virtual_host: "/"
        ],
        retry: [max_retries: 1, base_delay: 10]
      ]

      pid = start_supervised!({AMQPConnection, opts})
      assert Process.alive?(pid)

      conn = AMQPConnection.get_connection!(name)
      assert Process.alive?(conn.pid)

      # Verify we can open a channel through it
      assert {:ok, _} = AMQP.Channel.open(conn)
    end
  end

  describe "get_connection!/1" do
    test "returns alive connection", %{amqp_conn: real_conn} do
      name = unique_name(:connection)

      opts = [
        name: name,
        connection: [uri: rabbit_uri()],
        retry: [max_retries: 1, base_delay: 10]
      ]

      start_supervised!({AMQPConnection, opts})

      conn = AMQPConnection.get_connection!(name)
      assert Process.alive?(conn.pid)
      assert conn.pid != real_conn.pid
    end

    test "recovers after the underlying AMQP connection is killed", %{
      amqp_conn: _real_conn
    } do
      name = unique_name(:connection)

      opts = [
        name: name,
        connection: [uri: rabbit_uri()],
        retry: [max_retries: 5, base_delay: 50]
      ]

      start_supervised!({AMQPConnection, opts})

      conn = AMQPConnection.get_connection!(name)
      original_pid = conn.pid
      assert Process.alive?(original_pid)

      # Kill the underlying AMQP connection process
      Process.exit(original_pid, :kill)
      # Give the Connection GenServer time to receive DOWN and be restarted
      Process.sleep(300)

      fresh_conn = AMQPConnection.get_connection!(name)
      assert Process.alive?(fresh_conn.pid)
      assert fresh_conn.pid != original_pid
    end
  end

  describe "init/1 retry behavior" do
    test "stops with :max_connection_attempts_exceeded on bad URI" do
      name = unique_name(:connection)
      Process.flag(:trap_exit, true)

      opts = [
        name: name,
        connection: [uri: "amqp://guest:guest@localhost:9999"],
        retry: [max_retries: 2, base_delay: 10]
      ]

      assert {:error, :max_connection_attempts_exceeded} =
               AMQPConnection.start_link(opts)
    end
  end
end
