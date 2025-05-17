defmodule Ming.ReturningNilHandler do
  def execute(%Ming.ExampleCommand1{}, _context), do: nil
  def execute(%Ming.ExampleEvent1{}, _context), do: nil
end
