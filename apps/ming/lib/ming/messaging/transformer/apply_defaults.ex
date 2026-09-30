defmodule Ming.Messaging.Transformer.ApplyDefaults do
  @behaviour Ming.Messaging.Transformer

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Messaging.Transformer
  def encode(
        %Message{} = message,
        _args,
        %Context{metadata: %{ming_publication: publication}}
      ) do
    %Message{
      message
      | content_encoding: resolve_content_encoding(publication, message.content_encoding),
        content_type: resolve_content_type(publication, message.content_type),
        data_schema: resolve_data_schema(publication, message.content_encoding),
        data_ref: resolve_data_ref(publication, message.data_ref),
        headers: add_headers(publication, message.headers),
        reply_to: resolve_reply_to(publication, message.reply_to),
        source: resolve_source(publication, message.source),
        subject: resolve_subject(publication, message.subject),
        spec_version: resolve_spec_version(publication, message.spec_version),
        timestamp: resolve_time(message.timestamp),
        type: resolve_type(publication, message.type)
    }
  end

  @impl Ming.Messaging.Transformer
  def decode(
        %Message{} = message,
        _args,
        %Context{metadata: %{ming_subscription: subscription}}
      ) do
    %Message{
      message
      | content_encoding: resolve_content_encoding(subscription, message.content_encoding),
        content_type: resolve_content_type(subscription, message.content_type),
        data_schema: resolve_data_schema(subscription, message.content_encoding),
        data_ref: resolve_data_ref(subscription, message.data_ref),
        headers: add_headers(subscription, message.headers),
        reply_to: resolve_reply_to(subscription, message.reply_to),
        source: resolve_source(subscription, message.source),
        subject: resolve_subject(subscription, message.subject),
        spec_version: resolve_spec_version(subscription, message.spec_version),
        timestamp: resolve_time(message.timestamp),
        type: resolve_type(subscription, message.type)
    }
  end

  defp resolve_content_encoding(config, nil) when is_map(config) do
    Map.get(config, :default_content_encoding)
  end

  defp resolve_content_encoding(_config, content_encoding), do: content_encoding

  defp resolve_content_type(config, nil) when is_map(config) do
    Map.get(config, :default_content_type, "text/plain")
  end

  defp resolve_content_type(_config, content_type), do: content_type

  defp resolve_data_ref(config, nil) when is_map(config) do
    Map.get(config, :default_data_ref)
  end

  defp resolve_data_ref(_config, data_ref), do: data_ref

  defp resolve_data_schema(config, nil) when is_map(config) do
    Map.get(config, :default_data_schema)
  end

  defp resolve_data_schema(_config, data_schema), do: data_schema

  defp resolve_reply_to(config, nil) when is_map(config) do
    Map.get(config, :default_reply_to)
  end

  defp resolve_reply_to(_config, reply_to), do: reply_to

  defp resolve_source(config, %URI{host: "ming"} = source) when is_map(config) do
    Map.get(config, :default_source, source)
  end

  defp resolve_source(_config, source), do: source

  defp resolve_spec_version(config, "1.0") when is_map(config) do
    Map.get(config, :default_spec_version, "1.0")
  end

  defp resolve_spec_version(_config, spec_version), do: spec_version

  defp resolve_subject(config, nil) when is_map(config) do
    Map.get(config, :default_subject)
  end

  defp resolve_subject(_config, subject), do: subject

  defp resolve_time(nil), do: DateTime.utc_now()
  defp resolve_time(time), do: time

  defp resolve_type(config, "ming") when is_map(config) do
    Map.get(config, :default_type, "ming")
  end

  defp resolve_type(_config, type), do: type

  defp add_headers(config, headers) when is_map(config) do
    default_headers = Map.get(config, :default_headers, %{})

    Map.merge(default_headers, headers)
  end
end
