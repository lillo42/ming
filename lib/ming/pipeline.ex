defmodule Ming.Pipeline do
  @moduledoc """
  Defines the pipeline structure and operations for message processing in the Ming framework.

  The pipeline is a central data structure that carries the message, context, and state
  through various middleware stages during message processing. It maintains the request,
  response, metadata, and assigned values throughout the processing lifecycle.

  ## Pipeline Structure

  The pipeline is represented as a struct with the following fields:
  - `:application` - The application context or configuration

  - `:correlation_id` - A UUIDv7 identifier for tracing requests across services
  - `:request` - The incoming message or request to be processed
  - `:request_uuid` - Optional UUIDv7 identifier for the specific request
  - `:response` - The processed response or result
  - `:metadata` - Additional metadata for the processing context

  - `:assigns` - Key-value storage for arbitrary data between middleware
  - `:halted` - Boolean flag indicating if processing should stop

  ## Usage

  The pipeline flows through middleware stages (`before_dispatch`, `after_dispatch`, `after_failure`)
  where each middleware can transform the pipeline state, add metadata, or halt processing.
  """

  @type t :: %{
          application: term() | nil,
          correlation_id: UUIDv7.t(),
          request: any(),
          request_uuid: UUIDv7.t() | nil,
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

  @doc """
  Assigns a value to a key in the pipeline's assigns map.

  This function allows middleware to store arbitrary data in the pipeline context
  that can be accessed by subsequent middleware stages.

  ## Parameters
  - `pipeline`: The current `Ming.Pipeline.t()`
  - `key`: Atom key for the value
  - `value`: Value to store

  ## Returns
  - Updated `Ming.Pipeline.t()` with the new assignment


  ## Examples
      pipeline = Pipeline.assign(pipeline, :user_id, 123)
      pipeline.assigns.user_id # => 123
  """
  def assign(%__MODULE__{} = pipeline, key, value) when is_atom(key) do
    %__MODULE__{assigns: assigns} = pipeline

    %__MODULE__{pipeline | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Assigns a value to a key in the pipeline's metadata map.

  Metadata is used for storing processing context information that might be
  needed across different middleware components.

  ## Parameters
  - `pipeline`: The current `Ming.Pipeline.t()`
  - `key`: Atom or binary key for the metadata
  - `value`: Value to store

  ## Returns
  - Updated `Ming.Pipeline.t()` with the new metadata

  ## Examples
      pipeline = Pipeline.assign_metadata(pipeline, "timestamp", DateTime.utc_now())
      pipeline.metadata["timestamp"] # => ~U[2023-10-05 12:34:56Z]
  """
  def assign_metadata(%__MODULE__{} = pipeline, key, value) when is_binary(key) or is_atom(key) do
    %__MODULE__{metadata: metadata} = pipeline

    %__MODULE__{pipeline | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Checks if the pipeline has been halted.

  ## Parameters
  - `pipeline`: The `Ming.Pipeline.t()` to check

  ## Returns
  - `true` if processing is halted, `false` otherwise

  ## Examples
      Pipeline.halted?(pipeline) # => false
  """
  def halted?(%__MODULE__{halted: halted}), do: halted

  @doc """
  Halts the pipeline processing.

  Once halted, no further middleware will be executed for the current stage.

  ## Parameters
  - `pipeline`: The `Ming.Pipeline.t()` to halt

  ## Returns
  - Updated `Ming.Pipeline.t()` with halted flag set and error response

  ## Examples
      pipeline = Pipeline.halt(pipeline)
      Pipeline.halted?(pipeline) # => true
      Pipeline.response(pipeline) # => {:error, :halted}
  """
  def halt(%__MODULE__{} = pipeline) do
    %__MODULE__{pipeline | halted: true} |> respond({:error, :halted})
  end

  @doc """
  Retrieves the current response from the pipeline.

  ## Parameters
  - `pipeline`: The `Ming.Pipeline.t()` to inspect

  ## Returns
  - The current response value

  ## Examples
      Pipeline.response(pipeline) # => {:ok, result}
  """
  def response(%__MODULE__{response: response}), do: response

  @doc """
  Sets the response for the pipeline if no response is currently set.

  If the pipeline already has a response, this function is a no-op.

  ## Parameters
  - `pipeline`: The `Ming.Pipeline.t()` to update
  - `response`: The response value to set

  ## Returns
  - Updated `Ming.Pipeline.t()` with the new response

  ## Examples
      pipeline = Pipeline.respond(pipeline, {:ok, result})

      Pipeline.response(pipeline) # => {:ok, result}
  """
  def respond(%__MODULE__{response: nil} = pipeline, response) do
    %__MODULE__{pipeline | response: response}
  end

  def respond(%__MODULE__{} = pipeline, _response), do: pipeline

  @doc """
  Processes the pipeline through a list of middleware for a specific stage.

  This function recursively applies each middleware module to the pipeline

  for the given stage (e.g., `:before_dispatch`, `:after_dispatch`).

  Processing stops if:
  - The middleware list is empty
  - The pipeline is already halted
  - All middleware has been processed

  ## Parameters
  - `pipeline`: The current `Ming.Pipeline.t()`
  - `stage`: Atom representing the processing stage
  - `middleware`: List of middleware modules to apply

  ## Returns
  - Updated `Ming.Pipeline.t()` after processing all middleware


  ## Examples
      pipeline = Pipeline.chain(pipeline, :before_dispatch, [AuthMiddleware, LogMiddleware])
  """
  def chain(pipeline, stage, middleware)
  def chain(%__MODULE__{} = pipeline, _stage, []), do: pipeline
  def chain(%__MODULE__{halted: true} = pipeline, :before_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{halted: true} = pipeline, :after_dispatch, _middleware), do: pipeline

  def chain(%__MODULE__{} = pipeline, stage, [module | modules]) do
    chain(apply(module, stage, [pipeline]), stage, modules)
  end
end
