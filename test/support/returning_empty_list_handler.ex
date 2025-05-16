defmodule Ming.ReturningEmptyListHandler do
  def execute(%Ming.ExampleCommand1{}), do: []
  def execute(%Ming.ExampleEvent1{}), do: []
end
