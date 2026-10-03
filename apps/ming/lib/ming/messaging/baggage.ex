defmodule Ming.Messaging.Baggage do
  @moduledoc """
  Serializes W3C Trace Context `baggage` header values.

  `to_string/1` formats a map as comma-separated `key=value` pairs.
  `from_string/1` is reserved for parsing and is not implemented yet: it
  currently returns an empty map for any non-empty value.
  """

  import Kernel, except: [to_string: 1]

  @doc """
  Formats a baggage map as a comma-separated `key=value` header value.
  """
  def to_string(map) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.map_join(",", fn {key, value} ->
      "#{to_string(key)}=#{to_string(value)}"
    end)
  end

  def to_string(val), do: Kernel.to_string(val)

  @doc """
  Parses a `baggage` header value into a map.

  Not implemented yet: returns an empty map for any non-empty value, and
  `nil` for `nil` or an empty string.
  """
  def from_string(nil), do: nil
  def from_string(""), do: nil

  def from_string(val) when is_binary(val) do
    %{}
    # val
    # |> String.split(",")
    # |> Map.new(fn part ->
    #   nil
    # end)
  end
end
