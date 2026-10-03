defmodule Ming.Messaging.Baggage do
  @moduledoc """
  Parses and formats W3C Trace Context `baggage` header values.

  `to_string/1` formats a map as comma-separated `key=value` pairs.
  `from_string/1` parses the header back into a map, validating it against
  the standard: at most 64 members, keys as RFC 7230 tokens and values as
  `baggage-octet` sequences (printable ASCII except `"`, `,`, `;` and
  `\\`). Member properties (`;property` suffixes) are not represented in
  the map and are dropped. When the same key appears multiple times, the
  last value wins. An invalid header logs a warning and returns `nil`.
  """

  import Kernel, except: [to_string: 1]

  require Logger

  @max_entries 64

  # RFC 7230 token characters.
  @key_pattern ~r/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/

  # baggage-octet: %x21 / %x23-2B / %x2D-3A / %x3C-5B / %x5D-7E
  @value_pattern ~r/^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]*$/

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

  Returns `nil` for `nil`, an empty string, or an invalid header (a
  warning is logged in the invalid case).
  """
  def from_string(nil), do: nil
  def from_string(""), do: nil

  def from_string(val) when is_binary(val) do
    entries =
      val
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    if length(entries) <= @max_entries do
      entries
      |> Enum.reduce_while(%{}, fn entry, acc ->
        case parse_entry(entry) do
          {:ok, key, value} -> {:cont, Map.put(acc, key, value)}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:error, reason} -> invalid(val, reason)
        map -> map
      end
    else
      invalid(val, "expected at most #{@max_entries} entries, got #{length(entries)}")
    end
  end

  defp parse_entry(entry) do
    # Member properties (";...") are dropped: the map representation
    # cannot hold them.
    [member | _properties] = String.split(entry, ";")

    case String.split(member, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)

        cond do
          not Regex.match?(@key_pattern, key) ->
            {:error, "invalid key #{inspect(key)}"}

          not Regex.match?(@value_pattern, value) ->
            {:error, "invalid value #{inspect(value)} for key #{inspect(key)}"}

          true ->
            {:ok, key, value}
        end

      _malformed ->
        {:error, "malformed entry #{inspect(entry)}"}
    end
  end

  defp invalid(val, reason) do
    Logger.warning("invalid baggage header #{inspect(val)}: #{reason}; ignoring it")
    nil
  end
end
