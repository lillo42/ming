defmodule Ming.Messaging.Mapper do
  @moduledoc """
  Behaviour for mapping between application requests and
  `%Ming.Messaging.Message{}` payloads.

  A mapper is referenced as a module (`Ming.Messaging.Mapper.Json`), a
  `{module, args}` tuple, or the `:json` shorthand — use `resolve/1` to
  normalize any of these into `{module, args}`. The resolved `args` are
  passed through to both callbacks.
  """

  alias Ming.Context
  alias Ming.Messaging.Message

  @callback to_message(request :: any(), context :: Context.t(), args :: any()) ::
              Message.t()
              | Context.t()
              | {:ok, Message.t()}
              | {:error, any()}

  @callback to_request(message :: Message.t(), context :: Context.t(), args :: any()) ::
              any()
              | Context.t()
              | {:ok, any()}
              | {:error, any()}

  @doc """
  Resolves a mapper reference into a `{module, args}` tuple.
  """
  @spec resolve(:json | module() | {module(), keyword()}) :: {module(), keyword()}
  def resolve(:json), do: {Ming.Messaging.Mapper.Json, []}
  def resolve({module, args}), do: {module, args}
  def resolve(module) when is_atom(module), do: {module, []}
end
