defmodule Ming do
  @moduledoc """
  Ming is a lightweight, pipeline-based CQRS framework for Elixir.

  Requests are dispatched through `Ming.Dispatcher`: `send/2` routes a
  command to a single handler, `publish/2` fans an event out to every
  handler registered for the routing key. Each routing key maps to a
  `Ming.Pipeline` of `Ming.Middleware` ending in a `Ming.Handler`.
  """

  @typedoc """
  Key used to route a request to its pipeline.

  Defaults to the request struct module when not given explicitly.
  """
  @type routing_key :: atom() | binary()

  @typedoc """
  Normalized response of a dispatch.
  """
  @type resp :: :ok | {:ok, any()} | {:error, any()}

  @typedoc """
  Options accepted by `send` and `publish`.

    * `:routing_key` - overrides the inferred routing key
    * `:timeout` - pipeline timeout in milliseconds or `:infinity`
    * `:middlewares` - extra middleware appended for this dispatch
    * `:execution_strategy` - `:sequential`, `:parallel`, a module, or
      `{module, args}`
    * `:id`, `:correlation_id`, `:metadata`, `:timestamp` - context fields
  """
  @type dispatch_opts :: [
          routing_key: routing_key(),
          timeout: timeout(),
          middlewares: [Ming.Pipeline.middleware()],
          execution_strategy: :sequential | :parallel | module() | {module(), keyword()},
          id: any(),
          correlation_id: any(),
          metadata: map(),
          timestamp: DateTime.t()
        ]
end
