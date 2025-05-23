import Config

config :ming,
  message_mapper: Ming.JsonMapper,
  producers: [
    {Ming.InMemoryProducer, %{},
     [
       %{
         routing_key: "test"
       }
     ]}
  ]

# Print only warnings and errors during test
config :logger, level: :warning
