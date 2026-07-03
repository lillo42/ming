# Command Processor

A `Ming.CommandProcessor` is the main entry point for applications with multiple routers. It aggregates routers into a compile-time lookup table and can start the messaging gateway supervision tree automatically.

## Creating a command processor

```elixir
defmodule MyApp.CommandProcessor do
  use Ming.CommandProcessor, otp_app: :my_app

  router MyApp.UserRouter
  router MyApp.EventRouter
end
```

The `:otp_app` option tells the processor where to read gateway configuration from `Application.get_env/3`.

## Add it to the supervision tree

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.CommandProcessor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

## Sending commands

The processor automatically routes commands based on the struct module:

```elixir
{:ok, user} = MyApp.CommandProcessor.send(%MyApp.CreateUser{name: "Jane"})
```

When more than one router handles the same command struct, `send/2` returns `{:error, :more_than_one_handler_found}`.

## Publishing events

Events can be published to one or many routers:

```elixir
:ok = MyApp.CommandProcessor.publish(%MyApp.UserCreated{id: 123})

# Execute matching routers concurrently
MyApp.CommandProcessor.publish(%MyApp.UserCreated{id: 123}, dispatch_strategy: :parallel)
```

## Custom routing keys

For plain maps or runtime routing, pass a `:routing_key` option:

```elixir
MyApp.CommandProcessor.send(%{payload: "data"}, routing_key: :custom_key)
MyApp.CommandProcessor.publish(%{payload: "data"}, routing_key: :custom_key)
```

## Options

- `:otp_app` — required. The OTP application whose config holds gateway settings.
- `:default_message_mapper` — defaults to `Ming.Message.Mapper.Json`. Used by `post/2` when producing gateway messages.

## Posting messages through gateways

`post/2` publishes a message through the configured messaging gateway. See the [Gateways guide](gateways.html) for configuration details.

```elixir
MyApp.CommandProcessor.post(%MyApp.OrderCreated{id: 123})
```
