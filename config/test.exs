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
