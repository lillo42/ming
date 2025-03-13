defmodule Ming.Message do
  @moduledoc """
  The [message](https://www.enterpriseintegrationpatterns.com/patterns/messaging/Message.html) used to send message to a broker

  Thus any data that is to be transmitted via a messaging system must be converted into one or more messages that can be sent through messaging channels.

  A message consists of two basic parts:

  Header – Information used by the messaging system that describes the data being transmitted, its origin, its destination, and so on.
  Body – The data being transmitted; generally ignored by the messaging system and simply transmitted as-is.
  """

  @type message_type :: :unacceptable | :none | :command | :event | :document | :quit

  @type t :: %{
          extra_headers: map(),
          content_type: String.t() | nil,
          correlation_id: String.t() | nil,
          data_schema: URI.t() | nil,
          data_ref: String.t() | nil,
          delayed: Duration.t() | nil,
          handler_count: non_neg_integer(),
          id: String.t(),
          message_type: message_type(),
          partition_key: String.t() | nil,
          payload: binary(),
          reply_to: String.t() | nil,
          routing_key: String.t(),
          subject: String.t() | nil,
          spec_version: String.t(),
          source: URI.t(),
          time_stamp: DateTime.t(),
          type: String.t() | nil
        }

  @enforce_keys [
    :id,
    :message_type,
    :payload,
    :routing_key,
    :source,
    :time_stamp
  ]

  defstruct [
    :id,
    :message_type,
    :payload,
    :routing_key,
    :source,
    :time_stamp,
    extra_headers: %{},
    content_type: nil,
    correlation_id: nil,
    data_schema: nil,
    data_ref: nil,
    delayed: nil,
    handled_count: 0,
    partition_key: nil,
    reply_to: nil,
    subject: nil,
    spec_version: "1.0",
    type: nil
  ]
end
