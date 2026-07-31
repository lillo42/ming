import Config

# The gateway is started automatically by RabbitMQSample.CommandProcessor.
# Bring the broker up first (from the repository root):
#
#   docker compose -f docker-compose-rabbit-mq.yml up -d
#
config :rabbitmq_sample, RabbitMQSample.CommandProcessor,
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
        [routing_key: :order_shipped]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders.queue",
          routing_key: :order_shipped,
          # RabbitMQ 4.x rejects transient (non-durable) queues
          provision: {:create, durable: true}
        ]
      ]
    ]
  ]
