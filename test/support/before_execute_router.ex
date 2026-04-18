defmodule Ming.BeforeExecuteRouter do
  @moduledoc false

  use Ming.Router, ming: :ming

  alias Ming.BeforeExecuteHandler
  alias Ming.ExampleCommand1

  dispatch ExampleCommand1, to: BeforeExecuteHandler, before_execute: :before
end
