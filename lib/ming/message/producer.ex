defmodule Ming.Message.Producer do
  alias Ming.Message

  @type producer_publish_opts ::
          {:gateway, keyword()}
          | {:publication, Ming.publication_opts()}
          | {:extra_opts, keyword()}

  @callback publish(
              message_or_messages :: Message.t() | list(Message.t()),
              opts :: keyword(producer_publish_opts())
            ) ::
              Ming.resp()
end
