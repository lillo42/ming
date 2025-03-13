defmodule Ming.MessageProducer do
  @moduledoc """
  The behaviour for message producer, it's going to connect the Ming with a messaging gateway
  """

  @type publication :: %{
          content_type: String.t() | nil,
          data_schema: String.t() | nil,
          source: String.t() | nil,
          subject: String.t() | nil,
          routing_key: String.t(),
          type: String.t() | nil
        }

  @doc """
  Send a message to a messaging gateway
  """
  @callback send(message :: Message.t(), publication :: publication(), config :: any()) ::
              :ok | {:error, any()}

  @doc """
  Send a message to a messaging gateway with delay, if the messaging gateway doesn't support, we are going to send it
  """
  @callback send_with_delay(
              message :: Message.t(),
              delay :: Duration.t(),
              publication :: publication(),
              config :: any()
            ) ::
              :ok | {:error, any()}
end
