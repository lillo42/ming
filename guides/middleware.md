# Middleware

Ming's middleware engine is inspired by `Plug`. Middleware modules implement the `Ming.Middleware` behaviour and transform a `%Ming.Context{}` as it passes through the pipeline.

## Middleware behaviour

A middleware has two callbacks:

```elixir
defmodule MyApp.LoggingMiddleware do
  @behaviour Ming.Middleware

  @impl true
  def before_handle(%Ming.Context{} = context) do
    IO.puts("Starting #{context.routing_key}")
    context
  end

  @impl true
  def after_handle(%Ming.Context{} = context) do
    IO.puts("Finished #{context.routing_key}")
    context
  end
end
```

## Registering middleware

Middleware is registered in routers in declaration order:

```elixir
defmodule MyApp.UserRouter do
  use Ming.Router

  middleware MyApp.LoggingMiddleware
  middleware MyApp.AuthMiddleware

  register MyApp.CreateUser, handler: MyApp.UserHandler
end
```

## Modifying the context

Use `Ming.Context.assign/3` to share data between middlewares:

```elixir
def before_handle(%Ming.Context{} = context) do
  Ming.Context.assign(context, :start_time, System.monotonic_time())
end
```

## Halting execution

Use `Ming.Context.halt/1` to stop the pipeline early. Subsequent `before_handle` middlewares and the handler will not run, but registered `after_handle` middlewares still execute in reverse order.

```elixir
def before_handle(%Ming.Context{} = context) do
  if unauthorized?(context) do
    context
    |> Ming.Context.respond({:error, :unauthorized})
    |> Ming.Context.halt()
  else
    context
  end
end
```

## Telemetry and logging

Ming emits `:telemetry` span events around dispatch:

- `[:ming, :dispatch, :start]`
- `[:ming, :dispatch, :stop]`
- `[:ming, :dispatch, :exception]`

Timeouts and crashes are logged automatically with metadata such as `ming_routing_key`, `ming_handler`, and `ming_request_id`.

## Writing middleware for gateways

Gateway middleware receives the same `%Ming.Context{}` and can inspect `context.routing_key`, `context.assigns`, and other fields. Middleware registered on a router used for gateway consumption runs for every consumed message.
