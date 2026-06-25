defmodule Ming do
  @moduledoc """
  Core namespace for Ming.

  This module currently exposes shared project types used by the routing,
  dispatching, and handler contracts.
  """

  @typedoc """
  Common response shape expected by handlers and dispatch pipeline.
  """
  @type resp :: :ok | {:ok, any()} | {:error, any()}

  @typedoc """
  Represents a routing key used to map messages to their respective handlers.
  """
  @type routing_key :: atom()

  @typedoc """
  Represents a unique identifier, often a UUIDv7, string, or binary.
  """
  @type id :: UUIDv7.t() | String.t() | binary()

  @typedoc """
  Options allowed when sending a command via `Ming.CommandProcessor`.
  For `Ming.Router`, the routing key is a positional argument.
  """
  @type send_opts ::
          {:id, id()}
          | {:correlation_id, id()}
          | {:metadata, map()}
          | {:timeout, :infinity | non_neg_integer()}
          | {:routing_key, routing_key()}

  @typedoc """
  Specifies how multiple handlers should be executed.
  """
  @type dispatch_strategy :: :sequential | :parallel | {:parallel, Task.async_stream_option()}

  @typedoc """
  Options allowed when publishing an event.
  """
  @type publish_opts ::
          send_opts()
          | {:dispatch_strategy, dispatch_strategy()}

  @type provision_strategy :: :assume | :validate | :create | :create_or_override

  @type provision :: provision_strategy() | {provision_strategy(), any()}

  @type provision(t) :: {provision_strategy(), t}

  @type cloudevent_mode :: :binary | :json

  @type publication_opts ::
          {:additional_cloudevent_properties, map() | nil}
          | {:cloudevent_mode, cloudevent_mode()}
          | {:content_type, String.t() | atom() | nil}
          | {:data_schema, URI.t() | String.t() | nil}
          | {:default_headers, map() | nil}
          | {:provision, provision()}
          | {:reply_to, routing_key() | String.t() | URI.t() | nil}
          | {:routing_key, routing_key()}
          | {:source, URI.t() | String.t()}
          | {:spec_version, String.t() | nil}
          | {:subject, String.t() | nil}
          | {:topic_or_queue, String.t()}
          | {:type, String.t() | atom()}

  @type subscription_opts ::
          {:buffer_size, non_neg_integer()}
          | {:cloudevent_mode, cloudevent_mode()}
          | {:empty_delay, timeout()}
          | {:failure_delay, timeout()}
          | {:name, String.t() | atom()}
          | {:number_of_performers, non_neg_integer()}
          | {:processing_timeout, timeout()}
          | {:provision, provision()}
          | {:requeue_count, non_neg_integer() | nil}
          | {:requeue_delay, timeout()}
          | {:routing_key, routing_key()}
          | {:queue_or_topic, String.t() | atom() | URI.t()}
          | {:timeout, timeout()}
end
