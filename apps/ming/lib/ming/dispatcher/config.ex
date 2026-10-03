defmodule Ming.Dispatcher.Config do
  @moduledoc """
  Merges dispatcher configuration from `use Ming.Dispatcher` with
  application environment overrides.

  Keys merge plainly, except `:gateways`: gateways merge by name and,
  inside a gateway, `:publications` merge by `:routing_key` and
  `:subscriptions` by `:name`. An override replaces only the keys it sets
  on the matched entry, and base entries with no matching override are
  kept.
  """

  @doc """
  Merges the `overrides` keyword into the `default` dispatcher
  configuration.
  """
  def merge(default, overrides) do
    Keyword.merge(default, overrides, fn
      :gateways, base, extra -> merge_gateways(base, extra)
      _key, _base, extra -> extra
    end)
  end

  defp merge_gateways(base, overrides) do
    overrides = Enum.map(overrides, &normalize_gateway/1)

    Keyword.merge(base, overrides, fn _name, base_config, override_config ->
      merge_gateway(base_config, override_config)
    end)
  end

  defp merge_gateway(base, overrides) do
    Map.merge(base, overrides, fn
      :publications, base, extra -> merge_entries(base, extra, :routing_key)
      :subscriptions, base, extra -> merge_entries(base, extra, :name)
      _key, _base, extra -> extra
    end)
  end

  defp merge_entries(base, overrides, identity_key) do
    overrides = Enum.map(overrides, &normalize_entry/1)
    overridden = MapSet.new(overrides, &Map.get(&1, identity_key))

    Enum.map(overrides, fn override ->
      case Enum.find(base, &(Map.get(&1, identity_key) == Map.get(override, identity_key))) do
        nil -> override
        base_entry -> Map.merge(base_entry, override)
      end
    end) ++ Enum.reject(base, &(Map.get(&1, identity_key) in overridden))
  end

  defp normalize_gateway({name, {adapter, config}}) when is_atom(adapter) do
    {name,
     config
     |> Map.new()
     |> Map.put(:adapter, adapter)}
  end

  defp normalize_gateway({name, config}) when is_list(config) do
    {name, Map.new(config)}
  end

  defp normalize_gateway({name, config}) when is_map(config) do
    {name, config}
  end

  defp normalize_entry(entry) when is_list(entry), do: Map.new(entry)
  defp normalize_entry(entry) when is_map(entry), do: entry
end
