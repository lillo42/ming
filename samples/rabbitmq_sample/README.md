# RabbitMQ Sample — Ming + RabbitMQ (AMQP)

A minimal application showing how to configure Ming's **AMQP gateway** and
publish/consume messages through RabbitMQ.

- `config/config.exs` — gateway configuration, started automatically by
  `RabbitMQSample.CommandProcessor`.
- `lib/rabbitmq_sample/router.ex` — routes `:order_shipped` to
  `RabbitMQSample.OrderHandler`.
- `lib/rabbitmq_sample/order_handler.ex` — logs every consumed message.

## 1. Start the broker

From the repository root:

```sh
docker compose -f docker-compose-rabbit-mq.yml up -d
```

RabbitMQ listens on `localhost:5672` (management UI at
<http://localhost:15672>, guest/guest).

## 2. Start the sample

```sh
cd samples/rabbitmq_sample
mix deps.get
iex -S mix
```

On boot the gateway provisions the `events` topic exchange and the
`orders.queue` queue bound to it, then starts a pooled publisher and a
consumer with a pool of message processors.

## 3. Publish a message

Use `post/2` with the routing key of the gateway publication:

```elixir
RabbitMQSample.CommandProcessor.post(
  %RabbitMQSample.OrderShipped{id: 1, tracking_code: "BR123"},
  :order_shipped
)
```

A few moments later you should see the handler log line:

```
[info] consumed :order_shipped: %{"id" => 1, "tracking_code" => "BR123"} (correlation_id: ...)
```

The consumed payload arrives JSON-decoded (a plain map). The handler's return
value drives broker acks: `:ok`/`{:ok, _}` ack, `:reject` rejects without
requeue, `:requeue` rejects with requeue, `{:error, _}` rejects without
requeue.

## How it fits together

1. `post/2` wraps the request with the routing key and runs the internal
   `:ming_produce_message` pipeline, which resolves the matching gateway
   publication and publishes through a pooled AMQP channel
   (`Ming.Gateway.AMQP.Publisher`), with CloudEvents attributes as
   `cloudEvents:`-prefixed headers.
2. The subscription's consumer (`AMQP.Basic.consume`) receives the delivery,
   converts it to a `%Ming.Message{}`, and dispatches it into the processor
   through the internal `:ming_consume_message` pipeline via a pool of
   message processors.
3. The pipeline JSON-decodes the payload and re-dispatches it to the router
   using the subscription's `:routing_key`, ending in
   `RabbitMQSample.OrderHandler.handle/2`.

Notes:

- `:topic_or_queue` on a subscription is the queue to consume from.
- Pool options per publication/subscription: `:number_of_performers`
  (default 1), `:lazy`, `:idle_timeout`, `:idle_pings`.
- Provisioning supports `:assume` (default), `:validate`, `:create`, and
  `:create_or_override`, for both exchanges and queues.
- An optional `:dead_letter_exchange` can be configured alongside
  `:exchange`.
