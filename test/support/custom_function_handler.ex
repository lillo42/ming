defmodule Ming.CustomFunctionHandler do
  @moduledoc false

  def handle(%Ming.ExampleCommand1{}, _context), do: :ok
  def handle(%Ming.ExampleEvent1{}, _context), do: :ok
end
