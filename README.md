# Ming

Ming is a library focused on CQRS pattern, heavily inspired by [Brighter](https://github.com/BrighterCommand/Brighter) C# Framework and [Commanded](https://github.com/commanded/commanded/) Elixir library.

Provides support for:

- Command registration and dispatch
- Event registration and dispatch
- Query registration and dispatch
- Middleware pipeline for cross-cutting concerns
- Telemetry integration for monitoring

Requires Erlang/OTP v27 and Elixir v1.18 or later.

## Installation

Add `:ming` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ming, "~> 0.1.2"}
  ]
end
```

## Quick Start

### 1. Define a command and handler

```elixir
defmodule CreateUser do
  defstruct [:name, :email]
end

defmodule UserHandler do
  def execute(%CreateUser{} = command, _context) do
    # Business logic here
    :ok
  end
end
```

### 2. Create a router

```elixir
defmodule MyApp.Router do
  use Ming.Router, ming: :my_app

  middleware MyApp.AuthMiddleware
  middleware MyApp.LoggingMiddleware

  dispatch CreateUser, to: UserHandler
end
```

### 3. Send commands

```elixir
MyApp.Router.send(%CreateUser{name: "John", email: "john@example.com"})
```

### 4. Publish events

Events can be dispatched to multiple handlers concurrently:

```elixir
defmodule MyApp.PublishRouter do
  use Ming.PublishRouter, otp_app: :my_app, max_concurrency: 5

  publish UserCreated, to: UserProjection
  publish UserCreated, to: EmailNotifier
end
```

### 5. Execute queries

```elixir
defmodule MyApp.QueryRouter do
  use Ming.QueryRouter, otp_app: :my_app

  query GetUserById, to: UserQueryHandler
end
```

## Architecture

Ming follows a layered architecture:

1. **Router** (`Ming.Router`) - Unified command, event, and query routing
2. **Send/Publish/Query Routers** (`Ming.SendRouter`, `Ming.PublishRouter`, `Ming.QueryRouter`) - Specialized routing
3. **Composite Routers** (`Ming.CompositeRouter`, `Ming.SendCompositeRouter`, `Ming.PublishCompositeRouter`, `Ming.QueryCompositeRouter`) - Aggregate multiple routers
4. **CommandProcessor** (`Ming.CommandProcessor`) - Top-level command processing interface
5. **Dispatcher** (`Ming.Dispatcher`) - Core dispatching mechanism with middleware pipeline
6. **Pipeline** (`Ming.Pipeline`) - Middleware pipeline management

## Middleware

Middleware modules implement the `Ming.Middleware` behaviour and can intercept the pipeline at three stages:

- `before_dispatch/2` - Before handler execution
- `after_dispatch/2` - After successful handler execution
- `after_failure/2` - After handler failure

Middleware can be registered as a bare module or with options:

```elixir
middleware MyApp.AuthMiddleware
middleware {MyApp.LoggingMiddleware, level: :info}
```

## Telemetry

Ming emits the following telemetry events:

### Dispatch telemetry

- `[:ming, :application, :dispatch, :start]` - Dispatch started
- `[:ming, :application, :dispatch, :stop]` - Dispatch completed

Metadata includes `:application`, `:execution_context`, `:dispatcher_type` (`:command`, `:event`, `:query`), and `:error` on failure.

### Handler telemetry

- `[:ming, :handler, :execute, :start]` - Handler execution started
- `[:ming, :handler, :execute, :stop]` - Handler execution completed
- `[:ming, :handler, :execute, :exception]` - Handler raised an exception

## Used in production?

Not yet, it's a small project and still under active development.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/christopheradams/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.
