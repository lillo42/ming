# KafkaEx Sample — Ming + Apache Kafka via kafka_ex

A minimal application showing how to configure Ming's **Kafka gateway backed
by `:kafka_ex`** and how rejected and undecodable messages are routed to a
dead letter topic and an invalid message topic.

- `config/config.exs` — gateway configuration, started automatically by
  `KafkaExSample.CommandProcessor`. The `:orders` subscription sets
  `:dead_letter_queue_routing_key` and `:invalid_message_routing_key`.
- `lib/kafka_ex_sample/order_handler.ex` — rejects orders with a negative
  amount (they end up in the `orders.dlq` topic).
- `lib/kafka_ex_sample/dead_letter_handler.ex` — consumes the `orders.dlq`
  topic and logs every dead lettered message.

## 1. Start the broker

From the repository root:

```sh
docker compose -f docker-compose-kafka.yml up -d
```

Kafka listens on `localhost:9092` (no auth).

## 2. Start the sample

```sh
cd samples/kafka_ex_sample
mix deps.get
iex -S mix
```

On boot the gateway provisions the `orders`, `orders.dlq` and
`orders.invalid` topics and starts one `KafkaEx.Consumer.ConsumerGroup` per
subscription.

## 3. Publish a valid message

```elixir
KafkaExSample.CommandProcessor.post(
  %KafkaExSample.OrderCreated{id: 1, amount: 42},
  :order_created
)
```

A few moments later you should see:

```
[info] consumed :order_created: %{"amount" => 42, "id" => 1} (correlation_id: ...)
```

## 4. Dead letter a message

The handler rejects orders with a negative amount:

```elixir
KafkaExSample.CommandProcessor.post(
  %KafkaExSample.OrderCreated{id: 2, amount: -5},
  :order_created
)
```

Kafka has no native reject, so the gateway forwards the message to the
publication named by `:dead_letter_queue_routing_key` (the `orders.dlq`
topic) and commits the offset. The `:orders_dlq` subscription consumes it and
logs:

```
[warning] rejecting order with negative amount: %{"amount" => -5, "id" => 2} (routing_key: :order_created)
[warning] dead lettered :orders_dead_letter: %{"amount" => -5, "id" => 2} (correlation_id: ...)
```

The dead lettered message keeps the original payload and carries
`ORIGINAL_TIMESTAMP`, `ORIGINAL_TOPIC` and `ORIGINAL_TYPE` headers.

## 5. Send an invalid (poison) message

Produce a payload that is not valid JSON directly to the `orders` topic,
bypassing Ming's producer (the gateway client is registered as
`:kafka_gateway_client`):

```elixir
KafkaEx.API.produce(:kafka_gateway_client, "orders", 0, [%{value: "not json{{"}])
```

The consume pipeline fails to decode the payload and rejects it as
`:unaccepted`, so the gateway forwards it to the publication named by
`:invalid_message_routing_key` (the `orders.invalid` topic) and commits the
offset — the consumer keeps processing the next records instead of getting
stuck on the poison message.

Undecodable messages can never reach a handler (decoding happens before
routing), so there is intentionally no subscription on `orders.invalid`.
Inspect the forwarded message straight from the topic:

```elixir
{:ok, result} = KafkaEx.API.fetch_all(:kafka_gateway_client, "orders.invalid", 0)
[record] = result.records
record.value
# "not json{{"
Map.new(record.headers, &KafkaEx.Messages.Header.to_tuple/1)["ORIGINAL_TOPIC"]
# "orders"
```

## How it fits together

1. `post/2` wraps the request with the routing key and runs the internal
   `:ming_produce_message` pipeline, which resolves the matching gateway
   publication and publishes through the gateway producer (`KafkaEx`), with
   CloudEvents attributes as `ce_`-prefixed Kafka headers.
2. The subscription's `KafkaEx.Consumer.ConsumerGroup` receives records in
   batches, converts each one back to a `%Ming.Message{}`, and dispatches it
   into the processor through the internal `:ming_consume_message` pipeline.
3. The pipeline JSON-decodes the payload and re-dispatches it to the router
   using the subscription's `:routing_key`, ending in
   `KafkaExSample.OrderHandler.handle/2` — or, on decode failure, forwards
   the message to the invalid message topic.

Notes:

- `:topic_or_queue` is the Kafka topic and is required on both publications
  and subscriptions.
- The `KafkaEx` client is registered as `:kafka_gateway_client`
  (`:"#{name}_client"`); extra `:connection` keys go to
  `KafkaEx.API.start_client/1`.
- `:consumer_config`/`:group_config` are passed through to
  `KafkaEx.Consumer.ConsumerGroup` (e.g.
  `consumer_config: [auto_offset_reset: :earliest]`).
- Topic provisioning supports `:assume` (default), `:validate`, and
  `:create` / `{:create, num_partitions: ..., replication_factor: ...}`.
