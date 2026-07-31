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
- In-memory messaging gateway for local development and testing

Requires Erlang/OTP v27 and Elixir v1.18 or later.

## Installation

Add `:ming` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ming, "~> 0.2.0"}
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

  def handle(%CreateUser{}, %Ming.Context{} = context) do
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

:ok = MyApp.UserRouter.send(CreateUser, command)

# You can also pass send_opts, such as a custom timeout or correlation_id
:ok = MyApp.UserRouter.send(CreateUser, command, timeout: 5000)
```

Events can be published to multiple handlers registered to the same struct.

```elixir
defmodule MyApp.EventRouter do
  use Ming.Router

  register UserCreated, handler: UserProjection
  register UserCreated, handler: EmailNotifier
end

# Publish executes all registered handlers
MyApp.EventRouter.publish(UserCreated, %UserCreated{id: 123})

# Publish in parallel executes all registered handlers concurrently
MyApp.EventRouter.publish(UserCreated, %UserCreated{id: 123}, dispatch_strategy: :parallel)
```

### 4. Aggregating Routers with CommandProcessor

For larger applications, you can aggregate multiple routers into a single entry point using a `CommandProcessor`. This builds a compile-time lookup table to automatically forward payloads to the correct underlying router and can start the messaging gateway supervision tree for you.

```elixir
defmodule MyApp.CommandProcessor do
  use Ming.CommandProcessor, otp_app: :my_app

  router MyApp.UserRouter
  router MyApp.EventRouter
end

# Add it to your application supervision tree
children = [
  MyApp.CommandProcessor
]

# The processor automatically routes to UserRouter based on the struct
MyApp.CommandProcessor.send(%CreateUser{name: "Jane"})

# You can also use a custom routing key via opts
MyApp.CommandProcessor.send(%{payload: "data"}, routing_key: :custom_key)

# Similarly, publish supports passing options like `dispatch_strategy`
MyApp.CommandProcessor.publish(%UserCreated{id: 123}, dispatch_strategy: :parallel)
```

## Gateways

Ming supports messaging gateways for producing and consuming messages through external brokers. An in-memory gateway is included for local development and testing.

Gateways are configured under the command processor module in your application config and started automatically when the command processer starts.

### In-Memory Gateway

`Ming.Gateway.InMemory` routes messages directly inside the BEAM, with no external infrastructure. It is useful for local development, CI, and testing.

```elixir
# config/runtime.exs or config/config.exs
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.InMemory,
      name: :my_in_memory_gateway,
      publications: [
        [routing_key: :order_created]
      ],
      subscriptions: [
        [name: :orders, routing_key: :order_created]
      ]
    ]
  ]
```

You can publish messages through the in-memory gateway using `post/2` on your command processor module:

```elixir
MyApp.CommandProcessor.post(%OrderCreated{id: 123})
```

Consumed messages are dispatched through the configured command processor using the same `:ming_consume_message` pipeline as the AMQP gateway.

### AMQP Gateway

`Ming.Gateway.AMQP` connects to an AMQP broker (RabbitMQ, etc.) for production messaging. It manages connections, publisher pools, and consumers, and provisions exchanges and queues before startup.

```elixir
# config/runtime.exs or config/config.exs
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.AMQP,
      name: :my_amqp_gateway,
      connection: [
        uri: "amqp://guest:guest@localhost",
        retry: [max_retries: 5, base_delay: 1_000]
      ],
      exchange: [
        name: "events",
        type: :topic,
        provision: :create
      ],
      publications: [
        [routing_key: :order_created, number_of_performers: 2]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders.queue",
          routing_key: :order_created,
          # RabbitMQ 4.x rejects transient (non-durable) queues
          provision: {:create, durable: true}
        ]
      ]
    ]
  ]
```

For queues and exchanges, `:provision` also accepts `{:create, opts}` / `{:create_or_override, opts}`, where `opts` are passed to `AMQP.Queue.declare/3` / `AMQP.Exchange.declare/4` (e.g. `durable: true`). When provisioning, the queue is bound to the gateway exchange using the subscription's `:routing_key` as the binding key.

A runnable version of this setup is available in [`samples/rabbitmq_sample`](samples/rabbitmq_sample).

Add `:ming_amqp` to your dependencies to use the AMQP gateway:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:ming_amqp, "~> 0.2.0"}
  ]
end
```

Publishing and consuming work the same way as the in-memory gateway:

```elixir
MyApp.CommandProcessor.post(%OrderCreated{id: 123})
```

### Kafka Gateway

`Ming.Gateway.Brod` connects to Apache Kafka via `:brod`. It manages a single `:brod` client per gateway and one consumer group subscriber per subscription, and provisions topics before startup.

```elixir
# config/runtime.exs or config/config.exs
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.Brod,
      name: :my_kafka_gateway,
      connection: [
        endpoints: [{"localhost", 9092}]
      ],
      publications: [
        [routing_key: :order_created, topic_or_queue: "orders"]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders",
          routing_key: :order_created,
          group_id: "my-app",
          provision: {:create, num_partitions: 3, replication_factor: 1}
        ]
      ]
    ]
  ]
```

Add `:ming_brod` to your dependencies to use the Kafka gateway:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:ming_brod, "~> 0.2.0"}
  ]
end
```

`:topic_or_queue` is the Kafka topic and is required on both publications and subscriptions. `:group_id` defaults to the subscription name, and `:consumer_config`/`:group_config` are passed through to `:brod_group_subscriber_v2`. See the [gateways guide](guides/gateways.md) for the full option list.

A runnable version of this setup is available in [`samples/kafka_sample`](samples/kafka_sample).

### Kafka Gateway (kafka_ex)

`Ming.Gateway.KafkaEx` is an alternative Kafka gateway backed by the `:kafka_ex` library instead of `:brod`. It manages a single `KafkaEx` client per gateway and one `KafkaEx.Consumer.ConsumerGroup` per subscription, and provisions topics before startup. The configuration is identical to the `:brod` gateway, only the adapter changes:

```elixir
# config/runtime.exs or config/config.exs
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.KafkaEx,
      name: :my_kafka_gateway,
      connection: [
        endpoints: [{"localhost", 9092}]
      ],
      publications: [
        [routing_key: :order_created, topic_or_queue: "orders"]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders",
          routing_key: :order_created,
          group_id: "my-app",
          provision: {:create, num_partitions: 3, replication_factor: 1}
        ]
      ]
    ]
  ]
```

Add `:ming_kafka_ex` to your dependencies to use this Kafka gateway:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:ming_kafka_ex, "~> 0.2.0"}
  ]
end
```

`:consumer_config`/`:group_config` are passed through to `KafkaEx.Consumer.ConsumerGroup` (e.g. `consumer_config: [auto_offset_reset: :earliest]`). See the [gateways guide](guides/gateways.md) for the full option list.

## Samples

Complete runnable applications demonstrating the messaging gateways end to end:

- [`samples/kafka_sample`](samples/kafka_sample) — publish and consume through Apache Kafka
- [`samples/kafka_ex_sample`](samples/kafka_ex_sample) — kafka_ex gateway with dead letter and invalid message topics
- [`samples/rabbitmq_sample`](samples/rabbitmq_sample) — publish and consume through RabbitMQ (AMQP)

## Middleware Pipeline

Ming's middleware engine acts very much like Elixir's `Plug`. Middlewares implement the `Ming.Middleware` behaviour and receive the `Ming.Context`.

You can modify the context, share data between middlewares using `Context.assign/3`, or stop execution entirely using `Context.halt/1`.

```elixir
defmodule MyApp.LoggingMiddleware do
  @behaviour Ming.Middleware


  def before_handle(context) do
    IO.puts("Starting execution for #{context.routing_key}")
    context
  end

  def after_handle(context) do
    IO.puts("Finished execution. Halted? #{context.halted?}")
    context
  end
end
```

## Telemetry & Logging

Ming natively integrates with Erlang's `:telemetry` library and standard Elixir `Logger` metadata.

### Telemetry Events

Ming wraps the execution of the dispatcher in a `span`, emitting the following events:

- `[:ming, :dispatch, :start]` - Emitted when dispatch begins.
- `[:ming, :dispatch, :stop]` - Emitted when dispatch completes successfully. Includes calculated `duration`.
- `[:ming, :dispatch, :exception]` - Emitted if the pipeline raises an unhandled exception.

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
