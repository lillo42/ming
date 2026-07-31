import Config

# The gateway is started automatically by KafkaSample.CommandProcessor.
# Bring the broker up first (from the repository root):
#
#   docker compose -f docker-compose-kafka.yml up -d
#
config :kafka_sample, KafkaSample.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.Brod,
      name: :kafka_gateway,
      connection: [
        endpoints: [{"localhost", 9092}]
      ],
      publications: [
        [
          routing_key: :order_created,
          topic_or_queue: "orders",
          provision: :create
        ]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders",
          routing_key: :order_created,
          group_id: "kafka-sample",
          consumer_config: [begin_offset: :earliest],
          provision: :create
        ]
      ]
    ]
  ]
