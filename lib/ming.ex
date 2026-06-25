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
end
