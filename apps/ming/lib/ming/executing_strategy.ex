defmodule Ming.ExecutingStrategy do
  alias Ming.Context

  @callback execute(
              context :: Context.t(),
              pipelines :: list(Pipeline.t()),
              args :: any()
            ) :: Context.t()
end
