defmodule Ming.Message.Baggage do
  @moduledoc """
  Utilities for parsing and serializing W3C baggage header values.

  Baggage is a key-value format with optional metadata used for
  propagating context across message boundaries.
  """

  @doc """
  Stores a baggage value for the given key.
  """
  def put(map, key, val), do: Map.put(map, key, val)

  @doc """
  Stores a baggage value with optional metadata.

  The value is stored as a keyword list `[value: val, metadata: metadata]`
  and serialized accordingly by `to_string/1`.
  """
  def put(map, key, val, metadata), do: Map.put(map, key, value: val, metadata: metadata)

  @doc """
  Stores a baggage value with metadata only if the key does not already exist.
  """
  def put_new(map, key, val, metadata), do: Map.put_new(map, key, value: val, metadata: metadata)

  @doc """
  Parses a W3C baggage header string into a map.

  Returns an empty map for empty or blank strings.
  """
  def from_string(val)

  def from_string(val) when val == "" or is_nil(val), do: %{}

  def from_string(val) do
    val
    |> String.split(",")
    |> Enum.map(&extract_key_value_metadata(&1))
    |> Enum.reject(&is_nil(&1))
    |> Map.new()
  end

  defp extract_key_value_metadata(val) do
    [key_value | metadata] = String.split(val, ";")

    key_value =
      key_value
      |> String.split("=")
      |> extract_key_value()

    metadata = extract_metadata(metadata)

    cond do
      is_nil(key_value) ->
        nil

      metadata == [] ->
        key_value

      true ->
        {key, val} = key_value
        {key, [value: val, metadata: metadata]}
    end
  end

  defp extract_key_value([key, value]), do: {key, value}
  defp extract_key_value(_val), do: nil

  defp extract_metadata([]), do: []
  defp extract_metadata(["" | res]), do: extract_metadata(res)

  defp extract_metadata([value | res]) do
    acc = extract_metadata(res)

    split = String.split(value, "=")
    split_length = length(split)

    if split_length == 1 or split_length > 2 do
      [value | acc]
    else
      [key, val] = split
      [{key, val} | acc]
    end
  end

  @doc """
  Serializes a baggage map into a W3C baggage header string.

  Values are URL-encoded. Plain lists whose elements implement `String.Chars`
  are serialized as comma-separated strings. Keyword-list values are treated
  as `value + metadata` pairs. Complex values should be pre-encoded by the
  caller if cross-system round-tripping is required.
  """
  def to_string(val) when is_map(val) do
    val
    |> Map.to_list()
    |> Enum.map(&do_string(&1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  def to_string(nil), do: nil

  def to_string(val) when is_binary(val), do: val

  defp do_string({key, value}) when is_binary(value), do: "#{key}=#{URI.encode_www_form(value)}"

  defp do_string({key, value}) when is_list(value) do
    cond do
      Keyword.keyword?(value) ->
        serialize_keyword_list(key, value)

      Enum.all?(value, &implements_string_chars?/1) ->
        encoded =
          value
          |> Enum.map(&Kernel.to_string/1)
          |> Enum.map_join(",", &URI.encode_www_form/1)

        "#{key}=#{encoded}"

      true ->
        nil
    end
  end

  defp do_string({key, value}) do
    if String.Chars.impl_for(value) == nil do
      nil
    else
      value =
        value
        |> Kernel.to_string()
        |> URI.encode_www_form()

      "#{key}=#{value}"
    end
  end

  defp serialize_keyword_list(key, value) do
    val =
      Keyword.fetch!(value, :value)
      |> Kernel.to_string()
      |> URI.encode_www_form()

    metadata = Keyword.get(value, :metadata)

    cond do
      is_nil(metadata) ->
        "#{key}=#{val}"

      is_list(metadata) ->
        metadata =
          metadata
          |> Enum.map(&metadata_to_string(&1))
          |> Enum.reject(&is_nil/1)
          |> Enum.join(";")

        "#{key}=#{val};#{metadata}"

      true ->
        "#{key}=#{val};#{do_string(metadata)}"
    end
  end

  defp metadata_to_string({key, value}) when is_atom(value) do
    "#{key}=#{value}"
  end

  defp metadata_to_string({key, value}) when is_number(value) do
    "#{key}=#{value}"
  end

  defp metadata_to_string({key, value}) when is_binary(value) do
    "#{key}=#{URI.encode_www_form(value)}"
  end

  defp metadata_to_string({key, value}) do
    if String.Chars.impl_for(value) == nil do
      nil
    else
      "#{key}=#{URI.encode_www_form(Kernel.to_string(value))}"
    end
  end

  defp metadata_to_string(value) when is_atom(value) do
    Kernel.to_string(value)
  end

  defp metadata_to_string(value) when is_number(value) do
    Kernel.to_string(value)
  end

  defp metadata_to_string(value) when is_binary(value) do
    URI.encode_www_form(value)
  end

  defp metadata_to_string(value) do
    if String.Chars.impl_for(value) == nil do
      nil
    else
      URI.encode_www_form(Kernel.to_string(value))
    end
  end

  defp implements_string_chars?(value) do
    String.Chars.impl_for(value) != nil
  end
end
