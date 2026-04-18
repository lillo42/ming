defmodule Ming.ExecutionResultRouter do
  @moduledoc false

  use Ming.Router, ming: :ming

  alias Ming.ExampleCommand1
  alias Ming.ReturningNonEmptyListHandler

  dispatch ExampleCommand1, to: ReturningNonEmptyListHandler, returning: :execution_result
end
