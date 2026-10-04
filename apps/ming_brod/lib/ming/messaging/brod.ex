defmodule Ming.Messaging.Brod do
  @moduledoc """
  Kafka (brod) gateway for Ming.

  Bridges a `Ming.Dispatcher` to a Kafka cluster through `:brod`. One
  `:brod` client is started per gateway (named after the gateway), one
  `Ming.Messaging.Brod.Buffer` per subscription, and one
  `:brod_group_subscriber_v2` per subscription feeding that buffer.

  ## Configuration

      gateway :kafka, Ming.Messaging.Brod.Gateway,
        endpoints: [{"localhost", 9092}],
        client_config: [],
        publications: [
        [routing_key: "reports.generate", topic: "reports"]
        ],
        subscriptions: [
          [
            name: :reports,
            routing_key: "reports.generate",
            topic: "reports",
            group_id: "report-service"
          ]
        ]

    * `:endpoints` (required) — list of `{host, port}` bootstrap endpoints.
    * `:client_config` — extra `:brod` client configuration (SASL, SSL, ...).

  Publications accept `:topic` (defaults to the routing key as a string),
  `:partition`, `:partition_on_nil_key` and `:produce_mode` (`:sync` by
  default, `:async` for fire-and-forget).

  Subscriptions accept `:topic` (defaults to the routing key as a string),
  `:group_id` (defaults to `"ming-<gateway>-<topic>"`), `:consumer_config`
  and `:group_config` (passed to `:brod_group_subscriber_v2`; use
  `consumer_config: [prefetch_count: n, prefetch_bytes: n]` to bound the
  number of unprocessed messages in flight per partition), and
  `:receive_timeout` (how long `receive_messages/1` waits for messages,
  default 5s).

  Both publications and subscriptions accept a `:provisioner`
  (`:create` by default; also `:validate` and `:assume` — see
  `Ming.Messaging.Brod.Gateway`) and the topic settings
  `:num_partitions`, `:replication_factor` and `:topic_configs` (a map or
  keyword list of Kafka topic configuration entries, e.g.
  `[cleanup.policy: "compact"]`). Provisioning honours the gateway-level
  `:conn_config` and `:provision_timeout` (default 10s) options.

  ## Delivery semantics

  Consumption is at-least-once: a Kafka offset is only acked after the
  message is settled by `Ming.Messaging.BatchProcessing`. `nack` commits
  the offset (the message is not redelivered); `defer` commits the offset
  too, since Kafka has no deferred redelivery — the message is not
  redelivered and a warning is logged.
  """

  @doc """
  Returns the name of the per-gateway `Registry` that buffer processes
  register under. Started by the gateway itself; derived from the gateway
  name so both the gateway and the consumer can compute it from the
  subscription's `:gateway_name`.
  """
  def registry_name(gateway_name), do: Module.concat(gateway_name, Registry)

  @doc """
  Returns the process name of the buffer holding messages for the given
  subscription.
  """
  def buffer_name(subscription) do
    gateway_name = Map.fetch!(subscription, :gateway_name)
    key = {gateway_name, subscription_key(subscription)}
    {:via, Registry, {registry_name(gateway_name), key}}
  end

  @doc """
  Resolves the Kafka topic of a publication or subscription: the `:topic`
  option, defaulting to the routing key as a string.
  """
  def topic(entry), do: entry[:topic] || to_string(Map.fetch!(entry, :routing_key))

  defp subscription_key(subscription),
    do: Map.get(subscription, :name) || topic(subscription)
end
