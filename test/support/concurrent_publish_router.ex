defmodule Ming.ConcurrentPublishRouter do
  @moduledoc false

  use Ming.PublishRouter,
    otp_app: :ming,
    max_concurrency: 2

  alias Ming.ExampleEvent1
  alias Ming.ExampleHandler2
  alias Ming.ReturningErrorHandler

  publish(ExampleEvent1, to: ReturningErrorHandler)
  publish(ExampleEvent1, to: ExampleHandler2)
end
