defmodule Ming.Middleware do
  @moduledoc """
  Defines a behaviour for middleware components in the Ming message processing pipeline.

  This behaviour specifies callbacks that allow middleware modules to intercept and transform
  the pipeline at different stages of message processing. Middleware can modify the pipeline state,
  add logging, implement authentication, handle errors, or perform other cross-cutting concerns.

  ## Implementing the Behaviour

  To create a custom middleware module, implement this behaviour and define the required callbacks:

      defmodule MyMiddleware do
        @behaviour Ming.Middleware
        

        @impl true
        def before_dispatch(pipeline) do
          # Modify pipeline before dispatch
          pipeline
        end
        
        @impl true
        def after_dispatch(pipeline) do
          # Modify pipeline after successful dispatch
          pipeline
        end

        
        @impl true
        def after_failure(pipeline) do
          # Handle pipeline failures
          pipeline
        end
      end

  ## Pipeline Stages

  The middleware callbacks are called at these specific stages:

  1. `before_dispatch/1` - Before message dispatch to the broker
  2. `after_dispatch/1` - After successful message dispatch
  3. `after_failure/1` - After dispatch failure

  ## Usage

  Add middleware modules to your Ming pipeline configuration to enable them.
  Middleware are executed in the order they are configured.
  """

  @doc """
  Called before a message is dispatched to the message broker.

  This callback allows middleware to modify the pipeline state before the message
  is sent. Common use cases include:
  - Adding metadata or headers to the message
  - Implementing authentication/authorization checks
  - Validating message content or structure
  - Logging message details
  - Modifying message content or destination

  ## Parameters
  - `pipeline`: The current `Ming.Pipeline.t()` state containing message and context data

  ## Returns
  - Modified `Ming.Pipeline.t()` that will be used for dispatch

  ## Examples
      def before_dispatch(pipeline) do
        Logger.info("Dispatching message: \#{inspect(pipeline.message)}")
        # Add timestamp to message metadata
        Ming.Pipeline.put_metadata(pipeline, :timestamp, DateTime.utc_now())
      end

  """
  @callback before_dispatch(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @doc """
  Called after a message is successfully dispatched to the broker.

  This callback is invoked when the message has been successfully published
  but before the pipeline completes. Common use cases include:

  - Logging successful delivery
  - Updating delivery status in external systems
  - Cleaning up temporary resources
  - Sending notifications or triggering downstream actions
  - Recording metrics and performance data

  ## Parameters

  - `pipeline`: The current `Ming.Pipeline.t()` state after successful dispatch


  ## Returns
  - Modified `Ming.Pipeline.t()` for final processing


  ## Examples
      def after_dispatch(pipeline) do
        Logger.info("Message successfully dispatched to \#{pipeline.topic}")
        Metrics.increment("messages.sent")

        pipeline
      end

  """
  @callback after_dispatch(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @doc """
  Called when message dispatch fails at any point in the pipeline.

  This callback is invoked when an error occurs during message processing
  or dispatch. Common use cases include:
  - Error logging and diagnostics
  - Implementing retry logic or circuit breakers
  - Dead letter queue handling
  - Sending failure notifications
  - Cleaning up failed message state
  - Transforming errors for better reporting

  ## Parameters
  - `pipeline`: The current `Ming.Pipeline.t()` state containing error information


  ## Returns

  - Modified `Ming.Pipeline.t()` for error handling continuation


  ## Examples
      def after_failure(pipeline) do
        Logger.error("Dispatch failed: \#{inspect(pipeline.error)}")

        # Move message to dead letter queue
        DeadLetterQueue.add(pipeline.message, pipeline.error)
        pipeline
      end

  """
  @callback after_failure(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()
end
