defmodule Ming.Pipeline do
  @type t :: %{
          application: term() | nil,
          correlation_id: UUIDV7.t(),
          request: any(),
          request_uuid: UUIDV7.t() | nil,
          respose: any() | nil,
          metadata: map(),
          halted: boolean(),
          assigned: map()
        }

  defstruct [
    :application,
    :correlation_id,
    :request,
    :request_uuid,
    :metadata,
    :response,
    assigns: %{},
    halted: false
  ]

  def assign(%__MODULE__{} = pipeline, key, value) when is_atom(key) do
    %__MODULE__{assigns: assigns} = pipeline

    %__MODULE__{pipeline | assigns: Map.put(assigns, key, value)}
  end

  def assign_metadata(%__MODULE__{} = pipeline, key, value) when is_binary(key) or is_atom(key) do
    %__MODULE__{metadata: metadata} = pipeline

    %__MODULE__{pipeline | metadata: Map.put(metadata, key, value)}
  end

  def halted?(%__MODULE__{halted: halted}), do: halted

  def halt(%__MODULE__{} = pipeline) do
    %__MODULE__{pipeline | halted: true} |> respond({:error, :halted})
  end

  def response(%__MODULE__{response: response}), do: response

  def respond(%__MODULE__{response: nil} = pipeline, response) do
    %__MODULE__{pipeline | response: response}
  end

  def respond(%__MODULE__{} = pipeline, _response), do: pipeline

  def chain(pipeline, stage, middleware)
  def chain(%__MODULE__{} = pipeline, _stage, []), do: pipeline
  def chain(%__MODULE__{halted: true} = pipeline, :before_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{halted: true} = pipeline, :after_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{} = pipeline, stage, [module | modules]) do
    chain(apply(module, stage, [pipeline]), stage, modules)
  end
end
