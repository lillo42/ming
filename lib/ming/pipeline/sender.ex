defmodule Ming.Pipeline.Sender do
  @moduledoc """
  The middleware that send the message to messing gateway
  """

  @behaviour Ming.Pipeline.Middleware

  alias Ming.Message
  alias Ming.Pipeline
  import Ming.Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    pipeline
    |> fetch_producer()
    |> send_message()
  end

  defp fetch_producer(%Pipeline{} = pipeline) do
    producers = Application.get_env(:ming, :producers, [])

    assign_producer(pipeline, producers)
  end

  defp assign_producer(%Pipeline{} = pipeline, []) do
    pipeline
    |> halt()
    |> respond({:error, :message_producer_not_found})
  end

  defp assign_producer(%Pipeline{message: message} = pipeline, [producer | producers]) do
    publication =
      elem(producer, 2)
      |> Enum.find(fn p -> p.routing_key == message.routing_key end)

    if is_nil(publication) do
      assign_producer(pipeline, producers)
    else
      %Pipeline{pipeline | message_producer: {elem(producer, 0), elem(producer, 1), publication}}
    end
  end

  defp send_message(%Pipeline{halted: true} = pipeline), do: pipeline

  defp send_message(%Pipeline{} = pipeline) do
    %Pipeline{message: message, message_producer: producer, request: request} =
      pipeline

    {producer_module, config, publication} = producer

    message
    |> with_content_type(publication)
    |> with_data_schema(publication)
    |> with_source(publication)
    |> with_subject(publication)
    |> with_type(publication, request)

    case producer_module.send(message, publication, config) do
      :ok ->
        pipeline

      {:error, reason} ->
        pipeline
        |> halt()
        |> respond({:error, reason})
    end
  end

  defp with_content_type(
         %Message{content_type: content_type} = message,
         _publication
       )
       when not is_nil(content_type) and content_type != "" do
    message
  end

  defp with_content_type(
         %Message{} = message,
         %{content_type: content_type}
       )
       when not is_nil(content_type) and content_type != "" do
    %Message{
      message
      | content_type: content_type
    }
  end

  defp with_content_type(%Message{} = message, _publication) do
    message
  end

  defp with_data_schema(
         %Message{data_schema: data_schema} = message,
         _publication
       )
       when not is_nil(data_schema) do
    message
  end

  defp with_data_schema(
         %Message{} = message,
         %{data_schema: data_schema}
       )
       when not is_nil(data_schema) and data_schema != "" do
    %Message{
      message
      | data_schema: URI.parse(data_schema)
    }
  end

  defp with_data_schema(%Message{} = message, _publication) do
    message
  end

  defp with_source(
         %Message{source: source} = message,
         _publication
       )
       when not is_nil(source) do
    message
  end

  defp with_source(
         %Message{} = message,
         %{source: source}
       )
       when not is_nil(source) and source != "" do
    %Message{
      message
      | source: URI.parse(source)
    }
  end

  defp with_source(%Message{} = message, _publication) do
    message
  end

  defp with_subject(
         %Message{subject: subject} = message,
         _publication
       )
       when not is_nil(subject) and subject != "" do
    message
  end

  defp with_subject(
         %Message{} = message,
         %{subject: subject}
       )
       when not is_nil(subject) and subject != "" do
    %Message{
      message
      | subject: subject
    }
  end

  defp with_subject(%Message{} = message, _publication) do
    message
  end

  defp with_type(
         %Message{type: type} = message,
         _publication,
         _request
       )
       when not is_nil(type) and type != "" do
    message
  end

  defp with_type(
         %Message{} = message,
         %{type: type},
         _request
       )
       when not is_nil(type) and type != "" do
    %Message{
      message
      | type: type
    }
  end

  defp with_type(
         %Message{} = message,
         _publication,
         request
       )
       when is_struct(request) do
    %Message{
      message
      | type: to_string(request.__struct__)
    }
  end

  defp with_type(%Message{} = message, _publication, _request) do
    message
  end

  def after_dispatch(%Pipeline{} = pipeline), do: pipeline
  def after_failure(%Pipeline{} = pipeline), do: pipeline
end
