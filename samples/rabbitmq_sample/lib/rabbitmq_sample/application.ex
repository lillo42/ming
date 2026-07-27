defmodule RabbitMQSample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RabbitMQSample.CommandProcessor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: RabbitMQSample.Supervisor)
  end
end
