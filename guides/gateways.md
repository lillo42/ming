# Gateways

Ming supports messaging gateways for producing and consuming messages through external brokers. Gateways are configured under your command processor module and started automatically by the processor supervisor.

## Configuration

Gateway configuration is read from `Application.get_env(:my_app, MyApp.CommandProcessor)[:gateways]`.

```elixir
# config/runtime.exs or config/config.exs
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.InMemory,
      name: :my_gateway,
      publications: [
        [routing_key: :order_created]
      ],
      subscriptions: [
        [name: :orders, routing_key: :order_created]
      ]
    ]
  ]
```

The `:command_processor` option is injected automatically by `Ming.CommandProcessor` and should not be set manually.

## In-memory gateway

`Ming.Gateway.InMemory` routes messages inside the BEAM with no external infrastructure. It is useful for local development, CI, and testing.

```elixir
[
  adapter: Ming.Gateway.InMemory,
  name: :local_gateway,
  publications: [
    [routing_key: :order_created]
  ],
  subscriptions: [
    [name: :orders, routing_key: :order_created]
  ]
]
```

## AMQP gateway

`Ming.Gateway.AMQP` connects to RabbitMQ or another AMQP broker. It manages connections, publisher pools, and consumers, and can provision exchanges and queues before startup.

Add `:amqp` and `:nimble_pool` to your dependencies:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:amqp, "~> 4.1"},
    {:nimble_pool, "~> 1.1"}
  ]
end
```

Example configuration:

```elixir
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.AMQP,
      name: :amqp_gateway,
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
          provision: :create
        ]
      ]
    ]
  ]
```

## Publishing and consuming

Use `post/2` on your command processor module to publish a message through the configured gateway:

```elixir
MyApp.CommandProcessor.post(%MyApp.OrderCreated{id: 123})
```

Consumed messages are dispatched back through the command processor using the `:ming_consume_message` pipeline.

## Publication and subscription keys

- `:routing_key` inside `:publications` must be an atom and must be unique across all gateways.
- `:name` inside `:subscriptions` must be an atom and must be unique across all gateways.

## Provisioning strategies

- `:assume` — assume the exchange or queue already exists.
- `:validate` — verify the exchange or queue exists without creating it.
- `:create` — create the exchange or queue; fail if it already exists.
- `:create_or_override` — create or redeclare the exchange or queue.
