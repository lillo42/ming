defmodule Ming.ReturningEmptyListHandler do
  def execute(%Ming.ExampleCommand1{}, _context), do: []
  def execute(%Ming.ExampleEvent1{}, _context), do: []
end
