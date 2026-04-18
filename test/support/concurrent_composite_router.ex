defmodule Ming.ConcurrentCompositeRouter do
  @moduledoc false

  use Ming.PublishCompositeRouter,
    otp_app: :ming,
    max_concurrency: 2

  publish_router(Ming.ReturningErrorRouter)
  publish_router(Ming.ReturningOkRouter)
end
