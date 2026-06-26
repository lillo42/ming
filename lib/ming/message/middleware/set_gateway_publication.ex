defmodule Ming.Message.Middleware.SetGatewayPublication do
  alias Ming.Context

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def before_handle(
        %Context{
          metadata: %{
            message_routing_key: routing_key,
            default_message_mapper: default_message_mapper
          }
        } = context
      ) do
    gateways = Application.get_env(:ming, :gateways, [])

    publications =
      gateways
      |> Stream.flat_map(fn gateway ->
        gateway
        |> Keyword.get(:publication, [])
        |> Enum.map(&{gateway, &1})
      end)
      |> Stream.filter(fn {_gateway, publication} ->
        Keyword.fetch!(publication, :routing_key) == routing_key
      end)
      |> Enum.to_list()

    case Enum.count(publications) do
      0 ->
        context
        |> Context.halt()
        |> Context.respond({:error, {:publication_not_found, routing_key}})

      1 ->
        {gateway, publication} = Enum.at(publications, 0)

        mapper =
          Keyword.get(publication, :mapper) ||
            Keyword.get(gateway, :mapper, default_message_mapper)

        context
        |> Context.assign(:gateway, gateway)
        |> Context.assign(:publication, publication)
        |> Context.assign(:mapper, mapper)

      total ->
        context
        |> Context.halt()
        |> Context.respond({:error, {:multi_publication_found, routing_key, total}})
    end
  end

  def before_handle(%Context{} = context) do
    context
    |> Context.halt()
    |> Context.respond({:error, :invalid_context})
  end

  @impl Ming.Middleware
  def after_handle(context), do: context
end
