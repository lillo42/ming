defmodule Ming.TrackingRouter do
  @moduledoc false

  use Ming.Router,
    ming: :ming,
    max_concurrency: 2

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.ReturningErrorHandler
  alias Ming.ReturningOkHandler
  alias Ming.TrackingMiddleware

  middleware(TrackingMiddleware)

  dispatch(ExampleCommand1, to: ReturningOkHandler)
  dispatch(ExampleEvent1, to: ReturningErrorHandler)
  dispatch(ExampleEvent1, to: ReturningOkHandler)
end
