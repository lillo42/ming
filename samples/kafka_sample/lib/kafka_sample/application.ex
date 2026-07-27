defmodule KafkaSample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KafkaSample.CommandProcessor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: KafkaSample.Supervisor)
  end
end
