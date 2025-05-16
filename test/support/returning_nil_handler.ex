defmodule Ming.ReturningNilHandler do
  def execute(%Ming.ExampleCommand1{}), do: nil
  def execute(%Ming.ExampleEvent1{}), do: nil
end
