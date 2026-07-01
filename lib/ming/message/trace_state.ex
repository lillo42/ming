defmodule Ming.Message.TraceState do
  @moduledoc """
  Utilities for parsing and serializing W3C tracestate header values.

  Tracestate is a comma-separated list of key-value pairs used for
  propagating trace context across message boundaries.
  """

  @doc """
  Serializes a tracestate map into a comma-separated `key=value` string.

  Returns `nil` when given `nil`, and returns the value unchanged when it
  is not a map.
  """
  def to_string(val)

  def to_string(nil), do: nil

  def to_string(val) when is_map(val) do
    val
    |> Map.to_list()
    |> Enum.map_join(",", fn {key, value} -> "#{key}=#{value}" end)
  end

  def to_string(val), do: val

  @doc """
  Parses a W3C tracestate header string into a map.

  Malformed key-value pairs (those without exactly one `=`) are ignored.
  """
  def from_string(val)

  def from_string(nil), do: %{}
  def from_string(""), do: %{}

  def from_string(val) when is_binary(val) do
    if String.valid?(val) do
      val
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.filter(fn v -> length(v) == 2 end)
      |> Map.new(fn [key, val] -> {key, val} end)
    else
      %{}
    end
  end
end
