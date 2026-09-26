defmodule Ming.Messaging.TraceState do
  @moduledoc """
  Parses and formats W3C Trace Context `tracestate` header values.

  `from_string/1` validates the header against the standard: at most 32
  `key=value` entries, no duplicate keys, keys in the simple or
  `tenant@system` form, and values of 1-256 characters without commas or
  trailing spaces. An invalid header logs a warning and returns `nil`.
  """

  import Kernel, except: [to_string: 1]

  require Logger

  @max_entries 32

  # Simple key: a lowercase letter followed by up to 255 chars of
  # lcalpha/digit/"_"/"-"/"*"/"/". Tenant key: a tenant of up to 241 chars
  # (may start with a digit), "@", then a system of up to 14 chars.
  @key_pattern ~r/^(?:[a-z][a-z0-9_\-*\/]{0,255}|[a-z0-9][a-z0-9_\-*\/]{0,240}@[a-z][a-z0-9_\-*\/]{0,13})$/

  # 1-256 chars of printable ASCII except comma; the last char (and so the
  # value) may not be a trailing space.
  @value_pattern ~r/^[\x20-\x2B\x2D-\x3C\x3E-\x7E]{0,255}[\x21-\x2B\x2D-\x3C\x3E-\x7E]$/

  def to_string(map) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.map_join(",", fn {key, value} ->
      "#{to_string(key)}=#{to_string(value)}"
    end)
  end

  def to_string(val), do: Kernel.to_string(val)

  def from_string(nil), do: nil
  def from_string(""), do: nil

  def from_string(val) when is_binary(val) do
    entries =
      val
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    case validate(entries) do
      :ok ->
        Map.new(entries, fn entry ->
          [key, value] = String.split(entry, "=", parts: 2)
          {key, value}
        end)

      {:error, reason} ->
        Logger.warning("invalid tracestate header #{inspect(val)}: #{reason}; ignoring it")
        nil
    end
  end

  defp validate(entries) do
    with :ok <- validate_count(entries),
         :ok <- validate_entries(entries) do
      validate_duplicates(entries)
    end
  end

  defp validate_count(entries) do
    if length(entries) <= @max_entries do
      :ok
    else
      {:error, "expected at most #{@max_entries} entries, got #{length(entries)}"}
    end
  end

  defp validate_entries(entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case String.split(entry, "=", parts: 2) do
        [key, value] ->
          cond do
            not Regex.match?(@key_pattern, key) ->
              {:halt, {:error, "invalid key #{inspect(key)}"}}

            not Regex.match?(@value_pattern, value) ->
              {:halt, {:error, "invalid value #{inspect(value)} for key #{inspect(key)}"}}

            true ->
              {:cont, :ok}
          end

        _malformed ->
          {:halt, {:error, "malformed entry #{inspect(entry)}"}}
      end
    end)
  end

  defp validate_duplicates(entries) do
    keys = Enum.map(entries, fn entry -> entry |> String.split("=", parts: 2) |> hd() end)

    if length(keys) == length(Enum.uniq(keys)) do
      :ok
    else
      {:error, "duplicate keys"}
    end
  end
end
