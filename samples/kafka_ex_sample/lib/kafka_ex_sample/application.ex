defmodule KafkaExSample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KafkaExSample.CommandProcessor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: KafkaExSample.Supervisor)
  end
end
