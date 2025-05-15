defmodule Ming.ExampleRouter1 do
  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ExampleHandler1

  dispatch([ExampleCommand1, ExampleEvent1], to: ExampleHandler1)
  dispatch(ExampleEvent1, to: ExampleHandler2)
end
