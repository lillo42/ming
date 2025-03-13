defmodule Ming.Pipeline.Dispatcher do
  @moduledoc """
  The pipeline dispatcher
  """

  alias Ming.Pipeline

  def dispatch(request, metadata, middlewares) do
    pipeline = %Pipeline{request: request, metadata: metadata}

    pipeline = before_dispatch(pipeline, middlewares)

    if not Pipeline.halted?(pipeline) do
      pipeline
      |> after_dispatch(middlewares)
      |> Pipeline.response()
    else
      pipeline
      |> after_failure(middlewares)
      |> Pipeline.response()
    end
  end

  defp before_dispatch(%Pipeline{} = pipeline, middlewares) do
    Pipeline.chain(pipeline, :before_dispatch, middlewares)
  end

  defp after_dispatch(%Pipeline{} = pipeline, middleware) do
    Pipeline.chain(pipeline, :after_dispatch, middleware)
  end

  defp after_failure(%Pipeline{response: {:error, error}} = pipeline, middleware) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{response: {:error, error, reason}} = pipeline, middleware) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.assign(:error_reason, reason)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, middleware) do
    Pipeline.chain(pipeline, :after_failure, middleware)
  end
end
