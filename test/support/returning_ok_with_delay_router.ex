defmodule Ming.ReturningOkWithDelayRouter do
  @moduledoc false

  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ExampleHandler2
  alias Ming.ReturningOkWithDelayHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ReturningOkWithDelayHandler)
  dispatch(ExampleEvent1, to: ExampleHandler2)
end
