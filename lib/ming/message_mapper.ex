defmodule Ming.MessageMapper do
  @moduledoc """
  The behavior for map a map to message and message to map
  """
  alias Ming.Message

  @doc """
  Convert a map to a `Message`
  """
  @callback to_message(map :: any()) :: Message.t() | {:error, any()}

  @doc """
  Convert a `Message` to a `any()`
  """
  @callback to_map(message :: Message.t()) :: any() | {:error, any()}
end
