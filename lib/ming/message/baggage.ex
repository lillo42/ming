defmodule Ming.Message.Baggage do
  @moduledoc """
  Utilities for parsing and serializing W3C baggage header values.

  Baggage is a key-value format with optional metadata used for
  propagating context across message boundaries.
  """

  def put(map, key, val, metadata), do: Map.put(map, key, value: val, metadata: metadata)
  def put_new(map, key, val, metadata), do: Map.put_new(map, key, value: val, metadata: metadata)

  def from_string(val) when val == "", do: %{}

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

  def to_string(val) when is_map(val) do
    val
    |> Map.to_list()
    |> Enum.map_join(",", fn {key, value} -> "#{key}=#{do_string(value)}" end)
  end

  def to_string(val) when is_binary(val), do: val
  def to_string(val), do: val

  defp do_string(value) when is_list(value) do
    if Keyword.keyword?(value) do
      val = Keyword.fetch!(value, :value) |> Kernel.to_string()
      metadata = Keyword.get(value, :metadata)

      cond do
        is_nil(metadata) ->
          val

        is_list(metadata) ->
          "#{val};#{Enum.map_join(metadata, ";", &metadata_to_string(&1))}"

        true ->
          "#{val};#{do_string(metadata)}"
      end
    else
      do_string(value)
    end
  end

  defp do_string(value), do: URI.encode(Kernel.to_string(value))

  defp metadata_to_string({key, val}), do: "#{Kernel.to_string(key)}=#{Kernel.to_string(val)}"
  defp metadata_to_string(val), do: Kernel.to_string(val)
end
