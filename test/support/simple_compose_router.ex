defmodule Ming.SimpleComposeRouter do
  @moduledoc false

  use Ming.CompositeRouter

  router(Ming.ReturningOkRouter)
end
