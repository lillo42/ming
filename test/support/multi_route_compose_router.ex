defmodule Ming.MultiComposeRouter do
  use Ming.CompositeRouter

  router(Ming.ReturningOkRouter)

  router(Ming.ReturningEmptyListRouter)
end
