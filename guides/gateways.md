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

Add `:ming_amqp` to your dependencies:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:ming_amqp, "~> 0.2.0"}
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
          provision: {:create, durable: true}
        ]
      ]
    ]
  ]
```

Notes:

- RabbitMQ 4.x rejects transient (non-durable) queues — use
  `{:create, durable: true}` when provisioning queues.
- When provisioning, the queue is bound to the gateway exchange using the
  subscription's `:routing_key` as the binding key.
- Broker-native dead lettering: when the gateway configures
  `:dead_letter_exchange` and a subscription sets `:dead_letter` (a queue
  name), provisioning declares the dead letter queue, binds it to the dead
  letter exchange with the subscription's `:routing_key`, and declares the
  subscription queue with the `x-dead-letter-exchange` /
  `x-dead-letter-routing-key` arguments. From then on the broker itself
  dead-letters any message that is rejected without requeue (`:reject`,
  `{:reject, reason}`, `{:error, _}`) — including unacceptable messages
  that fail to decode.
- A runnable example is available in `samples/rabbitmq_sample`.

## Kafka gateway

`Ming.Gateway.Brod` connects to Apache Kafka via `:brod`. It manages a single `:brod` client per gateway, one consumer group subscriber per subscription, and can provision topics before startup.

Add `:ming_brod` to your dependencies:

```elixir
defp deps do
  [
    {:ming, "~> 0.2.0"},
    {:ming_brod, "~> 0.2.0"}
  ]
end
```

Example configuration:

```elixir
config :my_app, MyApp.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.Brod,
      name: :kafka_gateway,
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

Notes:

- `:topic_or_queue` is the Kafka topic and is required on both publications and subscriptions.
- The `:brod` client is registered as `:"#{name}_client"` (see `Ming.Gateway.Brod.client_name/1`).
- Any extra `:connection` keys are passed through to `:brod.start_link_client/3`.
- Subscription-only options:
  - `:group_id` — Kafka consumer group id, defaults to the subscription name.
  - `:processing_timeout` — timeout passed to the command processor, defaults to `:infinity`.
  - `:consumer_config` and `:group_config` — passed through to `:brod_group_subscriber_v2`.
  - `:requeue_routing_key` — routing key of a publication the message is republished to when the handler requeues it.
  - `:dead_letter_queue_routing_key` — routing key of a publication the message is forwarded to when the handler rejects it.
  - `:invalid_message_routing_key` — routing key of a publication an unacceptable message (one that fails to decode) is forwarded to; falls back to `:dead_letter_queue_routing_key` when not configured.
- Topic provisioning supports `:assume` (default), `:validate`, `:create`, and `{:create, opts}` where `opts` accepts `:num_partitions`, `:replication_factor`, and `:configs`.

Messages are published with CloudEvents attributes as `ce_`-prefixed Kafka headers and consumed back into `%Ming.Message{}` structs. Consumed messages are processed one at a time (`message_type: :message`) and acked per offset.

Handler results map to offsets as follows: `:ack` commits. `:reject` commits after forwarding the message to the publication named by the subscription's `:dead_letter_queue_routing_key` option, when configured (Kafka has no reject; the forwarded message carries `ORIGINAL_TIMESTAMP`, `ORIGINAL_TOPIC`, and `ORIGINAL_TYPE` headers). `:requeue` commits after republishing the message to the publication named by the subscription's `:requeue_routing_key` option, when configured (Kafka has no requeue) — without one, an error is logged (`"Kafka does not support requeue; the message was acked and will not be redelivered"`) and the message is acked.

## Publishing and consuming

Use `post/2` on your command processor module to publish a message through the configured gateway:

```elixir
MyApp.CommandProcessor.post(%MyApp.OrderCreated{id: 123})
```

Consumed messages are dispatched back through the command processor using the `:ming_consume_message` pipeline.

### Ack, reject, and requeue

The value returned by your handler (via the consumed pipeline) is translated into a broker acknowledgement:

- `:ok`, `{:ok, _}`, or `:ack` — acknowledge the message.
- `:reject` — reject without requeue (AMQP; the broker dead-letters the message when the queue was provisioned with a dead letter exchange) / forward to the subscription's `:dead_letter_queue_routing_key` publication when configured, then commit the offset (Kafka).
- `{:reject, reason}` — same transport behavior as `:reject`, carrying a reason. `{:reject, :unaccepted}` marks a poison message: it is also the automatic result when a message fails to decode, and on Kafka it is forwarded to the subscription's `:invalid_message_routing_key` publication (falling back to `:dead_letter_queue_routing_key`).
- `:requeue` — reject with requeue (AMQP) / republish to the subscription's `:requeue_routing_key` publication when configured, then commit the offset; without one, commit and log an error since Kafka has no requeue (Kafka).
- `{:error, _}` — reject without requeue (AMQP) / commit the offset to skip the message (Kafka).
- a raised exception — reject with requeue (AMQP) / commit the offset with the same error log as `:requeue` (Kafka).

## Publication and subscription keys

- `:routing_key` inside `:publications` must be an atom and must be unique across all gateways.
- `:name` inside `:subscriptions` must be an atom and must be unique across all gateways.

## Provisioning strategies

- `:assume` — assume the exchange or queue already exists.
- `:validate` — verify the exchange or queue exists without creating it.
- `:create` — create the exchange or queue; fail if it already exists.
- `:create_or_override` — create or redeclare the exchange or queue.
- `{:create, opts}` / `{:create_or_override, opts}` — same as above, passing
  `opts` to the declaration. For AMQP these go to `AMQP.Queue.declare/3` /
  `AMQP.Exchange.declare/4` (e.g. `durable: true`); for Kafka they accept
  `:num_partitions`, `:replication_factor`, and `:configs`.

The Kafka gateway supports `:assume`, `:validate`, and `:create` (or `{:create, opts}`) only.

## Samples

Complete runnable applications demonstrating the gateways end to end live in
the `samples/` directory:

- `samples/kafka_sample` — publish and consume through Apache Kafka
- `samples/rabbitmq_sample` — publish and consume through RabbitMQ (AMQP)
