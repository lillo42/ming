defmodule Ming.Message.Middleware.ResolvePublication do
  @moduledoc """
  Middleware that resolves the gateway, publication, and mapper for a
  message routing key.

  It looks up the configured `:ming` application gateways and selects the
  single publication matching `metadata.message_routing_key`. The selected
  gateway, publication, and mapper are stored in the context assigns for
  downstream middleware.
  """

  alias Ming.Context

  @behaviour Ming.Middleware

  @doc """
  Finds the unique publication for the current routing key.

  Halts with `{:error, {:publication_not_found, routing_key}}` if none is
  found, or `{:error, {:multi_publication_found, routing_key, total}}` if
  more than one matches. Halts with `{:error, :invalid_context}` when the
  required routing key metadata is missing.
  """
  @impl Ming.Middleware
  def before_handle(context)

  def before_handle(
        %Context{
          metadata: %{
            message_routing_key: routing_key,
            default_message_mapper: default_message_mapper
          }
        } = context
      ) do
    gateways = fetch_gateways(context)

    publications =
      gateways
      |> Stream.flat_map(fn gateway ->
        gateway
        |> Keyword.get(:publications, [])
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
        |> Context.assign(:ming_message_publication, publication)
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

  defp fetch_gateways(%Context{metadata: %{ming_application: app}}) do
    otp_app =
      if function_exported?(app, :__ming_otp_app__, 0) do
        app.__ming_otp_app__()
      else
        :ming
      end

    otp_app
    |> Application.get_env(app, [])
    |> Keyword.get(:gateways, [])
  end

  defp fetch_gateways(_context) do
    Application.get_env(:ming, :gateways, [])
  end

  @doc """
  No-op after stage.
  """
  @impl Ming.Middleware
  def after_handle(context), do: context
end
