# Getting Started

Ming is a lightweight, `Plug`-inspired pipeline framework for routing Commands, Queries, and Events in Elixir. It uses compile-time routing tables and a context-driven middleware pipeline.

This guide walks through creating your first command, handler, router, and command processor.

## Installation

Add `:ming` to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

Ming requires Erlang/OTP v27 and Elixir v1.18 or later.

## Define a command and handler

Commands (and events) are plain structs. Handlers implement the `Ming.Handler` behaviour and receive a `%Ming.Context{}`.

```elixir
defmodule MyApp.CreateUser do
  defstruct [:name, :email]
end

defmodule MyApp.UserHandler do
  @behaviour Ming.Handler

  @impl true
  def handle(%MyApp.CreateUser{name: name}, %Ming.Context{} = context) do
    # Business logic here
    Ming.Context.respond(context, {:ok, %{id: 123, name: name}})
  end
end
```

## Create a router

Routers map incoming requests to handlers and define middleware.

```elixir
defmodule MyApp.UserRouter do
  use Ming.Router

  middleware MyApp.LoggingMiddleware
  middleware MyApp.AuthMiddleware

  register MyApp.CreateUser, handler: MyApp.UserHandler
end
```

## Dispatch directly

You can send commands or publish events directly through a router.

```elixir
command = %MyApp.CreateUser{name: "Jane", email: "jane@example.com"}
{:ok, user} = MyApp.UserRouter.send(MyApp.CreateUser, command)
```

For events, use `publish/3` to execute all handlers registered for the same struct:

```elixir
MyApp.EventRouter.publish(MyApp.UserCreated, %MyApp.UserCreated{id: 123})
```

## Retrying failed requests

Registrations accept a `:retry` option. When the pipeline returns `{:error, _}` — including handler exceptions and timeouts — the whole pipeline is re-run with a backoff delay until it succeeds or the retries are exhausted:

```elixir
register MyApp.CreateUser,
  handler: MyApp.UserHandler,
  retry: [max_retries: 3, base_delay: 1_000, backoff_type: :rand_exp]
```

The option is a keyword list of `Ming.retry_opts()` (`:max_retries`, `:base_delay`, `:max_delay`, `:backoff_type` — one of `:rand_exp`, `:exp`, `:linear` or `:fixed`) or a plain integer meaning "retry up to N times with default backoff". A per-call `retry:` option overrides the registered one:

```elixir
MyApp.UserRouter.send(MyApp.CreateUser, command, retry: 0) # disable retries for this call
```

Each attempt runs the full middleware chain, emits its own `[:ming, :dispatch]` telemetry span, and a numeric `:timeout` applies per attempt.

## Next steps

- Learn how to aggregate routers in a [`CommandProcessor`](command_processor.html).
- Configure messaging [`Gateways`](gateways.html) such as InMemory or AMQP.
- Write custom [`Middleware`](middleware.html).
