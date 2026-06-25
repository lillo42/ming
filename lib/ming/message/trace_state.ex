defmodule Ming.Message.TraceState do
  def to_string(nil), do: nil

  def to_string(val) when is_map(val) do
    val
    |> Map.to_list()
    |> Enum.map_join(",", fn {key, value} -> "#{key}=#{value}" end)
  end

  def to_string(val), do: val

  def from_string(nil), do: %{}
  def from_string(""), do: %{}

  def from_string(val) when is_binary(val) do
    if String.valid?(val) do
      val
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.filter(fn v -> length(v) != 2 end)
      |> Map.new(fn [key, val] -> {key, val} end)
    else
      %{}
    end
  end
end
