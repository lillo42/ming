defmodule Ming.MultiComposeRouter do
  @moduledoc false

  use Ming.CompositeRouter

  router(Ming.ReturningOkRouter)

  router(Ming.ReturningEmptyListRouter)
end
