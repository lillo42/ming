# Ming

Ming is a lightweight, `Plug`-inspired pipeline framework for routing Commands, Queries, and Events in Elixir. 

While initially inspired by C# frameworks like Brighter, Ming has been completely rewritten to embrace Elixir's functional nature, relying on highly optimized compile-time routing and simple data transformations via `%Ming.Context{}`.

Provides support for:

- Command, Event, and Query registration and dispatch
- Unified Router architecture mapping payloads to handlers
- Aggregate dispatching via Command Processor
- A flexible, context-driven Middleware pipeline (similar to Plug)
- First-class `:telemetry` and structured logging integration
- Configurable execution timeouts

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

### 1. Define a struct and a handler

Handlers implement the `Ming.Handler` behaviour. They take a `%Ming.Context{}` and return it, optionally setting a response via `Ming.Context.respond/2`.

```elixir
defmodule CreateUser do
  defstruct [:name, :email]
end

defmodule UserHandler do
  @behaviour Ming.Handler

  def execute(%Ming.Context{request: %CreateUser{}} = context) do
    # Business logic here
    # ...
    Ming.Context.respond(context, :ok)
  end
end
```

### 2. Create a Router

Routers map incoming requests to their respective handlers and define the middleware pipeline.

```elixir
defmodule MyApp.UserRouter do
  use Ming.Router

  # Middleware runs in the order defined
  middleware MyApp.LoggingMiddleware
  middleware {MyApp.AuthMiddleware, role: :admin}

  register CreateUser, handler: UserHandler
end
```

### 3. Dispatching (Send and Publish)

You can send commands directly to a router.

```elixir
# Send expects a single handler to process the command
command = %CreateUser{name: "John", email: "john@example.com"}

%Ming.Context{response: :ok} = MyApp.UserRouter.send(command)
```

Events can be published to multiple handlers registered to the same struct.

```elixir
defmodule MyApp.EventRouter do
  use Ming.Router

  register UserCreated, handler: UserProjection
  register UserCreated, handler: EmailNotifier
end

# Publish executes all registered handlers
MyApp.EventRouter.publish(%UserCreated{id: 123})
```

### 4. Aggregating Routers with CommandProcessor

For larger applications, you can aggregate multiple routers into a single entry point using a `CommandProcessor`. This builds a compile-time lookup table to automatically forward payloads to the correct underlying router.

```elixir
defmodule MyApp.CommandProcessor do
  use Ming.CommandProcessor

  router MyApp.UserRouter
  router MyApp.EventRouter
end

# The processor automatically routes to UserRouter based on the struct
MyApp.CommandProcessor.send(%CreateUser{name: "Jane"})
```

## Middleware Pipeline

Ming's middleware engine acts very much like Elixir's `Plug`. Middlewares implement the `Ming.Middleware` behaviour and receive the `Ming.Context`.

You can modify the context, share data between middlewares using `Context.assign/3`, or stop execution entirely using `Context.halt/1`.

```elixir
defmodule MyApp.LoggingMiddleware do
  @behaviour Ming.Middleware

  def before_handle(context, _opts) do
    IO.puts("Starting execution for #{context.routing_key}")
    context
  end

  def after_handle(context, _opts) do
    IO.puts("Finished execution. Halted? #{context.halted?}")
    context
  end
end
```

## Telemetry & Logging

Ming natively integrates with Erlang's `:telemetry` library and standard Elixir `Logger` metadata.

### Telemetry Events

Ming wraps the execution of the dispatcher in a `span`, emitting the following events:

* `[:ming, :dispatch, :start]` - Emitted when dispatch begins.
* `[:ming, :dispatch, :stop]` - Emitted when dispatch completes successfully. Includes calculated `duration`.
* `[:ming, :dispatch, :exception]` - Emitted if the pipeline raises an unhandled exception.

All events include metadata such as `routing_key`, `handler`, `request_id`, and `correlation_id`.

### Structured Logging

If an execution timeout occurs or a pipeline crashes, Ming automatically logs the error via `Logger` using standard keyword list metadata:
`[ming_routing_key: ..., ming_handler: ..., ming_request_id: ..., crash_reason: ...]`

## Used in production?

Not yet, it's a small project and still under active development.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/christopheradams/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.
