defmodule Ming.ThrowRouter do
  @moduledoc false

  use Ming.Router

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ThrowHandler

  dispatch([ExampleCommand1, ExampleEvent1], to: ThrowHandler)
  dispatch(ExampleEvent1, to: ThrowHandler)
end
