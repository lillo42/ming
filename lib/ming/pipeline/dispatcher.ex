defmodule Ming.Pipeline.Dispatcher do
  @moduledoc """
  The pipeline dispatcher
  """

  alias Ming.Pipeline

  defmodule Payload do
    @moduledoc false

    @type t :: %Payload{}

    defstruct [
      :application,
      :command,
      :handler_module,
      :handler_function,
      :handler_before_execute,
      :timeout,
      :metadata,
      :retry_attempts,
      middleware: []
    ]
  end

  def dispatch(%Ming.Pipeline.Dispatcher.Payload{} = payload) do
    pipeline = to_pipeline(payload)

    pipeline = before_dispatch(pipeline, payload)

    if not Pipeline.halted?(pipeline) do
      pipeline
      |> after_dispatch(payload)
      |> Pipeline.respond(:ok)
      |> Pipeline.response()
    else
      pipeline
      |> after_failure(payload)
      |> Pipeline.response()
    end
  end

  defp to_pipeline(%Payload{} = payload) do
    struct(Pipeline, Map.from_struct(payload))
  end

  defp before_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :before_dispatch, middleware)
  end

  defp after_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :after_dispatch, middleware)
  end

  defp after_failure(%Pipeline{response: {:error, error}} = pipeline, %Payload{
         middleware: middleware
       }) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{response: {:error, error, reason}} = pipeline, %Payload{
         middleware: middleware
       }) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.assign(:error_reason, reason)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :after_failure, middleware)
  end
end
