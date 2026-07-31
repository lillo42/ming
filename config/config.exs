import Config

# The Ming KafkaEx gateway starts its own clients per gateway; no
# application-wide default worker is needed.
config :kafka_ex, disable_default_worker: true

import_config "#{Mix.env()}.exs"
