defmodule Ming.ReturningNonEmptyListRouter do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ExampleHandler2
  alias Ming.ReturningNonEmptyListHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningNonEmptyListHandler)
  dispatch(ExampleEvent1, to: ExampleHandler2)
end
