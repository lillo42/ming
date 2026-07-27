# Kafka Sample — Ming + Apache Kafka

A minimal application showing how to configure Ming's **Kafka gateway** and
publish/consume messages through an `orders` topic.

- `config/config.exs` — gateway configuration, started automatically by
  `KafkaSample.CommandProcessor`.
- `lib/kafka_sample/router.ex` — routes `:order_created` to
  `KafkaSample.OrderHandler`.
- `lib/kafka_sample/order_handler.ex` — logs every consumed message.

## 1. Start the broker

From the repository root:

```sh
docker compose -f docker-compose-kafka.yml up -d
```

Kafka listens on `localhost:9092` (no auth).

## 2. Start the sample

```sh
cd samples/kafka_sample
mix deps.get
iex -S mix
```

On boot the gateway provisions the `orders` topic and starts a `:brod`
consumer group (`kafka-sample`) subscribed to it.

## 3. Publish a message

Use `post/2` with the routing key of the gateway publication:

```elixir
KafkaSample.CommandProcessor.post(
  %KafkaSample.OrderCreated{id: 1, amount: 42},
  :order_created
)
```

A few moments later you should see the handler log line:

```
[info] consumed :order_created: %{"amount" => 42, "id" => 1} (correlation_id: ...)
```

The consumed payload arrives JSON-decoded (a plain map). The handler's return
value drives offset commits: `:ok`/`{:ok, _}` ack (commit), `:requeue` does
not commit (the message is redelivered), `:reject`/`{:error, _}` ack to skip
the message (Kafka has no reject).

## How it fits together

1. `post/2` wraps the request with the routing key and runs the internal
   `:ming_produce_message` pipeline, which resolves the matching gateway
   publication and publishes through the gateway producer (`:brod`), with
   CloudEvents attributes as `ce_`-prefixed Kafka headers.
2. The subscription's `:brod` group subscriber receives the record, converts
   it back to a `%Ming.Message{}`, and dispatches it into the processor
   through the internal `:ming_consume_message` pipeline.
3. The pipeline JSON-decodes the payload and re-dispatches it to the router
   using the subscription's `:routing_key`, ending in
   `KafkaSample.OrderHandler.handle/2`.

Notes:

- `:topic_or_queue` is the Kafka topic and is required on both publications
  and subscriptions.
- The `:brod` client is registered as `:kafka_gateway_client`
  (`:"#{name}_client"`); extra `:connection` keys go to
  `:brod.start_link_client/3`.
- Topic provisioning supports `:assume` (default), `:validate`, and
  `:create` / `{:create, num_partitions: ..., replication_factor: ...}`.
