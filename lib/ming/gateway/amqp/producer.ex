if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Producer do
    @moduledoc """
    Implementation of `Ming.Message.Producer` for the AMQP gateway.

    Converts `%Ming.Message{}` structs into AMQP Basic.publish calls via
    `Ming.Gateway.AMQP.Publisher`. Supports CloudEvents headers in both
    `:binary` and `:json` modes.
    """

    alias Ming.Message
    alias Ming.Message.Baggage
    alias Ming.Message.TraceState
    alias Ming.Gateway.AMQP.Publisher

    @behaviour Ming.Message.Producer

    @impl Ming.Message.Producer
    def publish(messages, opts) when is_list(messages),
      do: Enum.map(messages, &publish(&1, opts))

    def publish(%Message{} = message, opts) do
      gateway = Keyword.fetch!(opts, :gateway)
      publication = Keyword.fetch!(opts, :publication)
      extra_opts = Keyword.get(opts, :extra_opts, [])

      publish_opts =
        []
        |> put_if_not_nil(:app_id, Keyword.get(gateway, :app_id))
        |> put_if_not_nil(:content_encoding, Keyword.get(publication, :content_encoding))
        |> put_if_not_nil(:content_type, message.content_type)
        |> put_if_not_nil(:correlation_id, message.correlation_id)
        |> put_if_not_nil(:expiration, Keyword.get(extra_opts, :expiration))
        |> put_if_not_nil(:immediate, Keyword.get(publication, :immediate))
        |> put_if_not_nil(:mandatory, Keyword.get(publication, :mandatory))
        |> put_if_not_nil(:message_id, message.id)
        |> put_if_not_nil(:persistent, Keyword.get(publication, :persistent))
        |> put_if_not_nil(:priority, Keyword.get(extra_opts, :priority))
        |> put_if_not_nil(:reply_to, message.reply_to)
        |> put_if_not_nil(:timestamp, DateTime.to_unix(message.timestamp))
        |> put_headers(
          message,
          Keyword.get(publication, :default_headers, %{}),
          Keyword.get(publication, :cloudevent_mode, :binary)
        )

      exchange =
        gateway
        |> Keyword.fetch!(:config)
        |> Keyword.fetch!(:exchange)
        |> Keyword.fetch!(:name)

      routing_key = Keyword.fetch!(publication, :routing_key)

      Publisher.publish(
        routing_key,
        exchange,
        routing_key,
        message.payload,
        publish_opts
      )
    end

    defp put_if_not_nil(source, _key, nil), do: source
    defp put_if_not_nil(source, key, val) when is_map(source), do: Map.put(source, key, val)
    defp put_if_not_nil(source, key, val) when is_list(source), do: Keyword.put(source, key, val)

    defp put_headers(opts, %Message{headers: headers}, default_headers, :json) do
      Keyword.put(opts, :headers, to_amqp_headers(Map.merge(default_headers, headers)))
    end

    defp put_headers(opts, %Message{headers: headers} = message, default_headers, :binary) do
      headers =
        default_headers
        |> Map.merge(headers)
        |> put_if_not_nil("cloudEvents:id", message.id)
        |> put_if_not_nil("cloudEvents:baggage", Baggage.to_string(message.baggage))
        |> put_if_not_nil("cloudEvents:dataref", message.data_ref)
        |> put_if_not_nil("cloudEvents:dataschema", message.data_schema)
        |> put_if_not_nil("cloudEvents:specversion", message.spec_version)
        |> put_if_not_nil("cloudEvents:source", message.source)
        |> put_if_not_nil("cloudEvents:subject", message.subject)
        |> put_if_not_nil("cloudEvents:time", DateTime.to_iso8601(message.timestamp))
        |> put_if_not_nil("cloudEvents:traceparent", message.trace_parent)
        |> put_if_not_nil("cloudEvents:tracestate", TraceState.to_string(message.trace_state))
        |> put_if_not_nil("cloudEvents:type", message.type)

      Keyword.put(opts, :headers, to_amqp_headers(headers))
    end

    defp to_amqp_headers(headers) when is_map(headers) do
      headers
      |> Map.to_list()
      |> Enum.map(&to_amqp_header_value(&1))
    end

    defp to_amqp_header_value({key, nil}), do: {key, :void, :undefined}
    defp to_amqp_header_value({key, :undefined}), do: {key, :void, :undefined}
    defp to_amqp_header_value({key, val}) when is_integer(val), do: {key, :long, val}
    defp to_amqp_header_value({key, val}) when is_float(val), do: {key, :float, val}
    defp to_amqp_header_value({key, val}) when is_boolean(val), do: {key, :bool, val}
    defp to_amqp_header_value({key, val}) when is_atom(val), do: {key, :longstr, to_string(val)}
    defp to_amqp_header_value({key, {type, val}}) when is_atom(type), do: {key, type, val}

    defp to_amqp_header_value({key, %DateTime{} = val}),
      do: {key, :timestamp, DateTime.to_unix(val)}

    defp to_amqp_header_value({key, %Duration{} = val}),
      do: {key, :longstr, Duration.to_iso8601(val)}

    defp to_amqp_header_value({key, val}) when is_map(val),
      do:
        {key, :table,
         val
         |> Map.to_list()
         |> Enum.map(&to_amqp_header_value(&1))}

    defp to_amqp_header_value({key, val}) when is_binary(val) do
      if String.valid?(val) do
        {key, :longstr, val}
      else
        {key, :binary, val}
      end
    end

    defp to_amqp_header_value({key, val}) when is_list(val) do
      if Keyword.keyword?(val) do
        {key, :table, Enum.map(val, &to_amqp_header_value(&1))}
      else
        {key, :array,
         Enum.map(val, fn val ->
           {_key, type, value} = to_amqp_header_value({"_tmp", val})
           {type, value}
         end)}
      end
    end

    defp to_amqp_header_value({key, val}), do: {key, :longstr, to_string(val)}
  end
end
