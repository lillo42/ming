defmodule Ming.CustomFunctionRouter do
  @moduledoc false

  use Ming.PublishRouter, otp_app: :ming

  alias Ming.ExampleCommand1
  alias Ming.CustomFunctionHandler

  publish(ExampleCommand1, to: CustomFunctionHandler, function: :handle)
end
