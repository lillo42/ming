defmodule Ming.RaiseBeforeDispatchRouter do
  @moduledoc false

  use Ming.Router,
    ming: :ming,
    max_concurrency: 2

  alias Ming.ExampleCommand1
  alias Ming.ReturningOkHandler
  alias Ming.RaiseBeforeDispatchMiddleware

  middleware(RaiseBeforeDispatchMiddleware)

  dispatch(ExampleCommand1, to: ReturningOkHandler)
end
