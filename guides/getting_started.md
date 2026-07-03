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
  middleware {MyApp.AuthMiddleware, role: :admin}

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

## Next steps

- Learn how to aggregate routers in a [`CommandProcessor`](command_processor.html).
- Configure messaging [`Gateways`](gateways.html) such as InMemory or AMQP.
- Write custom [`Middleware`](middleware.html).
