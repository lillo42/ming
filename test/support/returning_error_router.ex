defmodule Ming.ReturningErrorRouter do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ReturningErrorHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningErrorHandler)
  dispatch(ExampleEvent1, to: ReturningErrorHandler)
end
