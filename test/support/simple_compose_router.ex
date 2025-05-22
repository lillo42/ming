defmodule Ming.SimpleComposeRouter do
  use Ming.CompositeRouter

  router(Ming.ReturningOkRouter)
end
