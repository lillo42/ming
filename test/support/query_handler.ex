defmodule Ming.QueryHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{}, _context), do: {:ok, :query_result}
  def execute(%Ming.ExampleEvent1{}, _context), do: {:ok, :query_result}
end
