defmodule Ming.ReturningOkHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{}, _context), do: :ok
  def execute(%Ming.ExampleEvent1{}, _context), do: :ok
end
