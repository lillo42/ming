defmodule Ming.RaiseHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{value: val}, _context) do
    raise ArgumentError, "invalid val: #{val}"
  end

  def execute(%Ming.ExampleEvent1{value: val}, _context) do
    raise ArgumentError, "invalid val: #{val}"
  end
end
