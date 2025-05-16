defmodule Ming.ReturningOkHandler do
  def execute(%Ming.ExampleCommand1{}), do: :ok
  def execute(%Ming.ExampleEvent1{}), do: :ok
end
