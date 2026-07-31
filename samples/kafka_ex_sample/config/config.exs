import Config

# The Ming KafkaEx gateway starts its own clients per gateway; no
# application-wide default worker is needed.
config :kafka_ex, disable_default_worker: true

# The gateway is started automatically by KafkaExSample.CommandProcessor.
# Bring the broker up first (from the repository root):
#
#   docker compose -f docker-compose-kafka.yml up -d
#
config :kafka_ex_sample, KafkaExSample.CommandProcessor,
  gateways: [
    [
      adapter: Ming.Gateway.KafkaEx,
      name: :kafka_gateway,
      connection: [
        endpoints: [{"localhost", 9092}]
      ],
      publications: [
        [
          routing_key: :order_created,
          topic_or_queue: "orders",
          provision: :create
        ],
        [
          routing_key: :orders_dead_letter,
          topic_or_queue: "orders.dlq",
          provision: :create
        ],
        [
          routing_key: :orders_invalid,
          topic_or_queue: "orders.invalid",
          provision: :create
        ]
      ],
      subscriptions: [
        [
          name: :orders,
          topic_or_queue: "orders",
          routing_key: :order_created,
          group_id: "kafka-ex-sample",
          consumer_config: [auto_offset_reset: :earliest],
          # rejected messages are forwarded to the :orders_dead_letter
          # publication ("orders.dlq" topic)
          dead_letter_queue_routing_key: :orders_dead_letter,
          # messages that fail to decode are forwarded to the
          # :orders_invalid publication ("orders.invalid" topic)
          invalid_message_routing_key: :orders_invalid,
          provision: :create
        ],
        [
          name: :orders_dlq,
          topic_or_queue: "orders.dlq",
          routing_key: :orders_dead_letter,
          group_id: "kafka-ex-sample-dlq",
          consumer_config: [auto_offset_reset: :earliest],
          provision: :create
        ]
      ]
    ]
  ]
