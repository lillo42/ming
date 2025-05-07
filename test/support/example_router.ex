defmodule Ming.ExampleRouter do
  use Ming.Router

  alias Ming.ExampleCommand

  dispatch(ExampleCommand, to: ExampleCommand)
  dispatch(ExampleCommand, to: ExampleCommand)
end
