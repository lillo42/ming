defmodule Ming.RaiseRouter do
  @moduledoc false

  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ExampleHandler2
  alias Ming.RaiseHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: RaiseHandler)
  dispatch(ExampleEvent1, to: ExampleHandler2)
end
