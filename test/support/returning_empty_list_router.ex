defmodule Ming.ReturningEmptyListRouter do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ReturningEmptyListHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningEmptyListHandler)
  dispatch(ExampleEvent1, to: ExampleHandler2)
end
