defmodule Ming.QueryRouterTestRouter do
  @moduledoc false

  use Ming.QueryRouter, otp_app: :ming

  alias Ming.ExampleCommand1
  alias Ming.ExampleEvent1
  alias Ming.QueryHandler

  query ExampleCommand1, to: QueryHandler
  query ExampleEvent1, to: QueryHandler
end
