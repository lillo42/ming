defmodule Ming.ReturningAKeyHandler do
  def execute(%Ming.ExampleCommand1{}, _context), do: :some_reply
  def execute(%Ming.ExampleEvent1{}, _context), do: :some_reply
end
