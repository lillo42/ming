defmodule Ming.ReturningNilHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{}, _context), do: nil
  def execute(%Ming.ExampleEvent1{}, _context), do: nil
end
