defmodule Ming.Messaging.Transformer do
  @moduledoc """
  Behaviour for transforming `%Ming.Messaging.Message{}` structs on their
  way out (`encode/3`) and in (`decode/3`).

  Transformers are declared on publications and subscriptions through the
  `:transformers` option, or dispatcher-wide with
  `Ming.Dispatcher.transformer/2`, and run in the order given by their
  `:order` option (default `1`). Ming ships with
  `Ming.Messaging.Transformer.ApplyDefaults`,
  `Ming.Messaging.Transformer.StructureCloudEvent`,
  `Ming.Messaging.Transformer.GzipCompression` and
  `Ming.Messaging.Transformer.ZipCompression`.

  A transformer may return the transformed message, `{:ok, message}`, an
  updated `%Ming.Context{}`, or `{:error, reason}` to halt the pipeline
  with an error.
  """

  alias Ming.Context
  alias Ming.Messaging.Message

  @doc """
  Transforms a message about to be published.
  """
  @callback encode(message :: Message.t(), args :: any(), context :: Context.t()) ::
              Message.t()
              | {:ok, Message.t()}
              | Context.t()
              | {:error, any()}

  @doc """
  Transforms a message about to be dispatched to its handler.
  """
  @callback decode(message :: Message.t(), args :: any(), context :: Context.t()) ::
              Message.t()
              | {:ok, Message.t()}
              | Context.t()
              | {:error, any()}
end
