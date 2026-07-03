defmodule Ming.Message.Mapper do
  @moduledoc """
  Behaviour for converting between domain requests and `%Ming.Message{}` structs.

  Used by middleware to bridge the Ming dispatch pipeline with messaging gateways.
  """

  alias Ming.Context
  alias Ming.Message

  @doc """
  Converts a domain request into a `%Ming.Message{}`.

  The returned message will be passed to a `Ming.Message.Producer` for publishing.
  """
  @callback to_message(request :: any(), context :: Context.t()) ::
              Message.t()
              | Context.t()
              | {:ok, Message.t()}
              | {:error, any()}

  @doc """
  Converts a `%Ming.Message{}` back into a domain request.

  The returned request will be dispatched through the Ming pipeline.
  """
  @callback to_request(message :: Message.t(), context :: Context.t()) ::
              any()
              | Context.t()
              | {:ok, any()}
              | {:error, any()}
end
