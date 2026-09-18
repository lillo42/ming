defmodule Ming.Handler do
  alias Ming.Context

  @callback handle(request :: any(), context :: Context.t()) :: Ming.resp()
end
