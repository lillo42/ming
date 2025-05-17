defmodule Ming.ReturningAKeyRouter do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ReturningAKeyHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningAKeyHandler)
  dispatch(ExampleEvent1, to: ReturningAKeyHandler)
end
