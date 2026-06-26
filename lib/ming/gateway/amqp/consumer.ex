if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP.Consumer do
    @moduledoc """
    GenServer that consumes messages from an AMQP queue and dispatches
    them into the Ming pipeline via `Ming.Gateway.AMQP.MessageProcess`.

    Incoming messages are parsed into `%Ming.Message{}` structs with
    CloudEvents and W3C trace context support.
    """

    use GenServer

    alias AMQP.Basic
    alias AMQP.Channel

    alias Ming.Gateway.AMQP.Connection
    alias Ming.Gateway.AMQP.MessageProcess
    alias Ming.Message
    alias Ming.Message.Baggage
    alias Ming.Message.TraceState

    @doc """
    Starts the consumer linked to the current process.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(args) do
      gateway_name = Keyword.fetch!(args, :gateway_name)

      conn = Connection.get_connection!(gateway_name)
      {:ok, channel} = Channel.open(conn)

      topic_or_queue = Keyword.fetch!(args, :topic_or_queue)
      name = Keyword.fetch!(args, :name)
      routing_key = Keyword.fetch!(args, :routing_key)

      buffer_size = Keyword.get(args, :buffer_size, 1)
      number_of_performers = Keyword.get(args, :number_of_performers, 1)

      with :ok <- Basic.qos(channel, prefetch_count: buffer_size * number_of_performers),
           {:ok, _val} <- Basic.consume(channel, topic_or_queue) do
        {:ok,
         %{
           channel: channel,
           name: name,
           routing_key: routing_key,
           timeout: Keyword.get(args, :processing_timeout, :infinity)
         }}
      else
        {:error, reason} ->
          :ok = Channel.close(channel)
          {:stop, reason}
      end
    end

    @impl true
    def terminate(_reason, state) do
      try do
        Channel.close(state.channel)
      rescue
        _exception -> nil
      catch
        _e -> nil
      end

      :ok
    end

    @impl true
    def handle_info({:basic_consumer_ok, _meta}, state) do
      {:noreply, state}
    end

    def handle_info({:basic_cancel, _meta}, state) do
      {:stop, :stopped_by_amqp, state}
    end

    def handle_info({:basic_cancel_ok, _meta}, state) do
      {:stop, :stopped_by_client, state}
    end

    def handle_info(
          {:basic_deliver, payload, metadata},
          %{
            channel: channel,
            name: name,
            routing_key: routing_key,
            timeout: timeout
          } = state
        ) do
      message = to_message(payload, metadata, routing_key)

      MessageProcess.process(
        name,
        channel,
        Map.fetch!(metadata, :delivery_tag),
        routing_key,
        message,
        timeout
      )

      {:noreply, state}
    end

    @doc """
    Converts an AMQP delivery into a `%Ming.Message{}`.

    CloudEvents attributes are extracted from AMQP headers when present.
    """
    @spec to_message(binary(), map(), Ming.routing_key()) :: Message.t()
    def to_message(payload, metadata, routing_key) do
      headers =
        parse_headers(Map.get(metadata, :headers))
        |> Map.put(:amqp_metadata, metadata)

      message_id =
        Map.get(headers, "cloudEvents:id") || Map.get(metadata, :message_id, UUIDv7.generate())

      timestamp =
        parse_timestamp(Map.get(headers, "cloudEvents:time") || Map.get(metadata, :timestamp))

      %Message{
        id: message_id,
        baggage: Baggage.from_string(Map.get(headers, "cloudEvents:baggage")),
        content_type: Map.get(metadata, :content_type),
        correlation_id: Map.get(metadata, :correlation_id, UUIDv7.generate()),
        data_ref: Map.get(headers, "cloudEvents:dataref"),
        data_schema: parse_uri(Map.get(headers, "cloudEvents:dataschema")),
        headers: headers,
        payload: payload,
        reply_to: Map.get(metadata, :reply_to),
        routing_key: routing_key,
        spec_version: Map.get(headers, "cloudEvents:specversion", "1.0"),
        source: parse_uri(Map.get(headers, "cloudEvents:source", "https://hex.pm/packages/ming")),
        subject: Map.get(headers, "cloudEvents:subject"),
        timestamp: timestamp,
        trace_parent: Map.get(headers, "cloudEvents:traceparent"),
        trace_state: TraceState.from_string(Map.get(headers, "cloudEvents:tracestate")),
        type: Map.get(headers, "cloudEvents:type")
      }
    end

    defp parse_headers(nil), do: %{}
    defp parse_headers(:undefined), do: %{}
    defp parse_headers([]), do: %{}

    defp parse_headers(val) when is_list(val), do: Map.new(val, &parse_header_value(&1))

    defp parse_header_value({key, :void, _val}), do: {key, nil}
    defp parse_header_value({key, _type, nil}), do: {key, nil}
    defp parse_header_value({key, :table, []}), do: {key, %{}}
    defp parse_header_value({key, :table, val}), do: {key, Map.new(val, &parse_header_value(&1))}

    defp parse_header_value({key, :array, []}), do: {key, []}

    defp parse_header_value({key, :array, val}) do
      {key,
       Enum.map(val, fn {type, value} ->
         parse_header_value({"_tmp", type, value})
         |> elem(1)
       end)}
    end

    defp parse_header_value({key, :timestamp, val}) do
      case DateTime.from_unix(val, :second) do
        {:ok, datetime} ->
          {key, datetime}

        {:error, _reason} ->
          {key, val}
      end
    end

    defp parse_header_value({key, _type, val}), do: {key, val}

    defp parse_timestamp(nil), do: DateTime.utc_now()

    defp parse_timestamp(val) when is_number(val) do
      case DateTime.from_unix(val, :second) do
        {:ok, datetime} ->
          datetime

        {:error, _reason} ->
          DateTime.utc_now()
      end
    end

    defp parse_timestamp(val) when is_binary(val) do
      case DateTime.from_iso8601(val) do
        {:ok, datetime, _calendar} ->
          datetime

        {:error, _reason} ->
          DateTime.utc_now()
      end
    end

    defp parse_uri(nil), do: nil

    defp parse_uri(val) do
      case URI.new(val) do
        {:ok, uri} ->
          uri

        {:error, _reason} ->
          val
      end
    end
  end
end
