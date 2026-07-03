defmodule Ming.Message.Producer do
  @moduledoc """
  Behaviour for message producers that publish `%Ming.Message{}` structs.

  Implementations are responsible for sending messages to a messaging gateway
  (e.g. AMQP, Kafka, etc.).
  """

  alias Ming.Message

  @typedoc """
  Options passed to `publish/2`.
  """
  @type producer_publish_opts ::
          {:gateway, keyword()}
          | {:publication, Ming.publication_opts()}
          | {:extra_opts, keyword()}

  @doc """
  Publishes one or more `%Ming.Message{}` structs to the configured gateway.

  Returns `:ok` or `{:ok, result}` on success, `{:error, reason}` on failure.
  """
  @callback publish(
              message_or_messages :: Message.t() | list(Message.t()),
              opts :: keyword(producer_publish_opts())
            ) ::
              Ming.resp()
end
