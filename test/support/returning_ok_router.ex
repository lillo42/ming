defmodule Ming.ReturningOkRouter do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ReturningOkHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningOkHandler)
  dispatch(ExampleEvent1, to: ReturningOkHandler)
end
