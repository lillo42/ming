defmodule Ming.ReturningErrorHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{}, _context), do: {:error, :some_error}
  def execute(%Ming.ExampleEvent1{}, _context), do: {:error, :some_error}
end
