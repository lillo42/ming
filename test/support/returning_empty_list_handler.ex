defmodule Ming.ReturningEmptyListHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{}, _context), do: []
  def execute(%Ming.ExampleEvent1{}, _context), do: []
end
