defmodule Ming.Pipeline.MapMessage do
  @moduledoc """
  An internal `Ming.Pipeline.Middleware` that map the `orignal_request` to `Message`.
  """
  @behaviour Ming.Pipeline.Middleware

  alias Ming.Message
  alias Ming.Pipeline

  import Ming.Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    fetch_message_mapper(pipeline)
    |> convert_to_message()
  end

  defp fetch_message_mapper(%Pipeline{message_mapper: mapper}) when not is_nil(mapper) do
    mapper
  end

  defp fetch_message_mapper(%Pipeline{} = pipeline) do
    mapper = Application.get_env(:ming, :message_map)

    if is_nil(mapper) do
      pipeline
      |> halt()
      |> respond({:error, :message_mapper_not_found})
    else
      %Pipeline{pipeline | message_mapper: mapper}
    end
  end

  defp convert_to_message(%Pipeline{halted: true} = pipeline), do: pipeline

  defp convert_to_message(%Pipeline{} = pipeline) do
    %Pipeline{message_mapper: mapper, request: request} = pipeline

    case mapper.to_message(request) do
      %Message{} = message ->
        %Pipeline{pipeline | message: message}

      {:error, error} ->
        pipeline
        |> halt()
        |> respond(error)
    end
  end

  def after_dispatch(%Pipeline{} = pipeline), do: pipeline
  def after_failure(%Pipeline{} = pipeline), do: pipeline
end
