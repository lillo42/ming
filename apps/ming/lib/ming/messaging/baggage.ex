defmodule Ming.Messaging.Baggage do
  import Kernel, except: [to_string: 1]

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
    %{}
    # val
    # |> String.split(",")
    # |> Map.new(fn part ->
    #   nil
    # end)
  end
end
