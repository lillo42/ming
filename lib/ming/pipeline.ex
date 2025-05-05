defmodule Ming.Pipeline do
  @moduledoc """
  Pipeline is a struct used as an argument in the callback functions of modules
  implementing the `Ming.Middleware` behaviour.

  This struct must be returned by each function to be used in the next
  middleware based on the configured middleware chain.

  ## Pipeline fields

    - `application` - the Ming application.
    
    - `assigns` - shared user data as a map.

    - `correlation_id` - an optional UUID used to correlate related
       commands/events together.

    - `request` - command struct being dispatched.

    - `request_uuid` - UUID assigned to the command being dispatched.

    - `consistency` - requested dispatch consistency, either: `:eventual`
       (default) or `:strong`.

    - `halted` - flag indicating whether the pipeline was halted.

    - `metadata` - the metadata map to be persisted along with the events.

    - `response` - sets the response to send back to the caller.
  """

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

  @doc """
  Puts the `key` with value equal to `value` into `assigns` map.
  """
  def assign(%__MODULE__{} = pipeline, key, value) when is_atom(key) do
    %__MODULE__{assigns: assigns} = pipeline

    %__MODULE__{pipeline | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Puts the `key` with value equal to `value` into `metadata` map.

  Note: Use of atom keys in metadata is deprecated in favour of binary strings.
  """
  def assign_metadata(%__MODULE__{} = pipeline, key, value) when is_binary(key) or is_atom(key) do
    %__MODULE__{metadata: metadata} = pipeline

    %__MODULE__{pipeline | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Has the pipeline been halted?
  """
  def halted?(%__MODULE__{halted: halted}), do: halted

  @doc """

  Halts the pipeline by preventing further middleware downstream from being invoked.


  Prevents dispatch of the command if `halt` occurs in a `before_dispatch` callback.
  """
  def halt(%__MODULE__{} = pipeline) do
    %__MODULE__{pipeline | halted: true} |> respond({:error, :halted})
  end

  @doc """
  Extract the response from the pipeline
  """
  def response(%__MODULE__{response: response}), do: response

  @doc """
  Sets the response to be returned to the dispatch caller, unless already set.
  """
  def respond(%__MODULE__{response: nil} = pipeline, response) do
    %__MODULE__{pipeline | response: response}
  end

  def respond(%__MODULE__{} = pipeline, _response), do: pipeline

  @doc """
  Executes the middleware chain.
  """
  def chain(pipeline, stage, middleware)
  def chain(%__MODULE__{} = pipeline, _stage, []), do: pipeline
  def chain(%__MODULE__{halted: true} = pipeline, :before_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{halted: true} = pipeline, :after_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{} = pipeline, stage, [module | modules]) do
    chain(apply(module, stage, [pipeline]), stage, modules)
  end
end
