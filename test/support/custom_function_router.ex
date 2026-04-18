defmodule Ming.CustomFunctionRouter do
  @moduledoc false

  use Ming.PublishRouter, otp_app: :ming

  alias Ming.CustomFunctionHandler
  alias Ming.ExampleCommand1

  publish(ExampleCommand1, to: CustomFunctionHandler, function: :handle)
end
