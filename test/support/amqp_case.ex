defmodule Ming.Gateway.AMQP.Case do
  @moduledoc """
  Test case for AMQP integration tests against a live RabbitMQ broker.

  Assumes RabbitMQ is running at `amqp://guest:guest@localhost:5672`.
  Start it with:

      docker compose -f docker-compose-rabbit-mq.yml up -d
  """

  use ExUnit.CaseTemplate

  alias AMQP.{Channel, Connection}

  @rabbit_uri "amqp://guest:guest@localhost:5672"

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup do
    case Connection.open(@rabbit_uri) do
      {:ok, conn} ->
        {:ok, chan} = Channel.open(conn)
        on_exit(fn -> cleanup(chan, conn) end)
        [amqp_conn: conn, amqp_chan: chan, exchange: unique_name("exchange")]

      {:error, reason} ->
        raise """
        RabbitMQ is not running at #{@rabbit_uri} (#{inspect(reason)}).
        Start it with: docker compose -f docker-compose-rabbit-mq.yml up -d
        """
    end
  end

  @doc """
  Returns a unique name for an exchange or queue.
  """
  def unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  @doc """
  Closes the channel and connection.
  """
  def cleanup(chan, conn) do
    try do
      Channel.close(chan)
    catch
      _, _ -> :ok
    end

    try do
      Connection.close(conn)
    catch
      _, _ -> :ok
    end

    :ok
  end

  @doc """
  Returns the default RabbitMQ URI used by tests.
  """
  def rabbit_uri, do: @rabbit_uri
end
