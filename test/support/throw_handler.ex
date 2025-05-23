defmodule Ming.ThrowHandler do
  @moduledoc false

  def execute(%Ming.ExampleCommand1{value: val}, _context) do
    throw(val)
  end

  def execute(%Ming.ExampleEvent1{value: val}, _context) do
    throw(val)
  end
end
