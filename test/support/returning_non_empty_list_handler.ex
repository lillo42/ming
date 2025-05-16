defmodule Ming.ReturningNonEmptyListHandler do
  def execute(%Ming.ExampleCommand1{}), do: [:some_reply]
  def execute(%Ming.ExampleEvent1{}), do: [:some_reply]
end
