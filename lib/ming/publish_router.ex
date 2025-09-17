defmodule Ming.PublishRouter do
  @moduledoc """
  Provides a routing system for publishing and handling events in the Ming framework.

  This module enables event-driven architecture by allowing events to be published
  to multiple handlers concurrently. It supports both synchronous and asynchronous

  event publishing with configurable concurrency, timeouts, and retry mechanisms.

  ## Key Features

  - Event registration and routing to multiple handlers
  - Synchronous and asynchronous event publishing

  - Configurable concurrency control for parallel event processing
  - Middleware support for cross-cutting concerns
  - Telemetry integration for monitoring event processing
  - Error aggregation for handling multiple handler failures

  ## Usage

  Use this module to create event routers that handle event publication:

      defmodule MyApp.PublishRouter do
        use Ming.PublishRouter, 
          otp_app: :my_app,
          timeout: 10_000,

          max_concurrency: 5

        publish_middleware MyApp.EventValidationMiddleware
        publish_middleware MyApp.EventLoggingMiddleware

        publish_dispatch UserCreated, to: UserProjection
        publish_dispatch UserCreated, to: EmailNotifier
        publish_dispatch OrderPlaced, to: OrderProcessor, timeout: 30_000
      end

  Then you can publish events:

      # Synchronous publishing
      MyApp.PublishRouter.publish(%UserCreated{id: 123, name: "John"})

      # Asynchronous publishing  
      task = MyApp.PublishRouter.publish_async(%OrderPlaced{order_id: "456", amount: 100.0})
      Task.await(task)
  """

  alias Ming.Dispatcher.Payload

  @doc """
  Sets up the PublishRouter module with configuration options.

  This macro is invoked when using `Ming.PublishRouter` in another module.
  It registers module attributes and sets default configuration values for event publishing.

  ## Options
  - `:otp_app` - The OTP application name (default: `:ming`)
  - `:timeout` - Default timeout for event processing in milliseconds (default: `5000`)
  - `:retry` - Default number of retry attempts for failed event processing (default: `10`)
  - `:concurrency_timeout` - Timeout for concurrent event processing (default: `30000`)
  - `:max_concurrency` - Maximum number of concurrent event handlers (default: `1`)
  - `:task_supervisor` - Task supervisor for async operations (default: `Ming.TaskSupervisor`)

  ## Examples
      use Ming.PublishRouter,
        otp_app: :my_app,
        timeout: 15_000,
        max_concurrency: 10,
        concurrency_timeout: 60_000
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    timeout = Keyword.get(opts, :timeout, 5_000)
    retry_attempts = Keyword.get(opts, :retry, 10)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 30_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_publish_requests, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_publish_middleware, accumulate: true)

      @task_supervisor unquote(task_supervisor)

      @default_publish_dispatch_opts [
        application: unquote(otp_app),
        timeout: unquote(timeout),
        metadata: %{},
        retry_attempts: unquote(retry_attempts),
        concurrency_timeout: unquote(concurrency_timeout),
        max_concurrency: unquote(max_concurrency),
        before_execute: nil,
        returning: false
      ]
    end
  end

  @doc """
  Registers middleware for event processing.

  Middleware modules are executed in the order they are registered and can
  intercept and transform events before they reach their handlers.

  ## Parameters
  - `middleware_module` - The middleware module to register

  ## Examples

      publish_middleware MyApp.EventValidationMiddleware
      publish_middleware MyApp.EventEnrichmentMiddleware
  """
  defmacro publish_middleware(middleware_module) do
    quote do
      @registered_publish_middleware unquote(middleware_module)
    end
  end

  @doc """
  Registers an event or events for dispatch to specific handlers.

  This macro generates the necessary functions to route events to their
  appropriate handlers with the specified configuration options.

  ## Parameters
  - `request_module_or_modules` - A single event module or list of event modules
  - `opts` - Configuration options for event dispatch

  ## Options
  - `:to` - The handler module that will process the event (required)
  - `:function` - The handler function to call (default: `:execute`)
  - `:before_execute` - Optional function to prepare the event before execution
  - `:timeout` - Timeout for this specific event (overrides default)
  - `:metadata` - Additional metadata for the execution context
  - `:retry_attempts` - Number of retry attempts for this event
  - `:returning` - Specifies what should be returned from execution

  ## Examples
      # Single event to single handler
      publish_dispatch UserCreated, to: UserProjection

      # Single event to multiple handlers
      publish_dispatch UserCreated, to: UserProjection
      publish_dispatch UserCreated, to: EmailNotifier

      # Multiple events to same handler
      publish_dispatch [OrderCreated, OrderUpdated, OrderDeleted], to: OrderProjection

      # With custom options
      publish_dispatch PaymentProcessed,
        to: AccountingService,
        function: :handle_payment,
        timeout: 30_000
  """
  defmacro publish_dispatch(request_module_or_modules, opts) do
    opts = parse_publish_opts(opts, [])

    for request_module <- List.wrap(request_module_or_modules) do
      quote do
        @registered_publish_requests {
          unquote(request_module),
          Keyword.merge(@default_publish_dispatch_opts, unquote(opts))
        }
      end
    end
  end

  @typedoc """
  Response type for publish operations.

  Can be one of:
  - `:ok` - All event handlers processed successfully
  - `{:error, errors}` - One or more handlers failed, with list of errors
  """
  @type publish_resp :: :ok | {:error, any()}

  @doc """
  Callback for publishing events synchronously.

  This callback provides a consistent interface for synchronous event publishing.
  """
  @callback publish(event :: struct()) :: publish_resp()

  @doc """
  Callback for publishing events synchronously with options or timeout.

  This callback provides a consistent interface for synchronous event publishing
  with additional configuration options.
  """
  @callback publish(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: publish_resp()

  @doc """
  Callback for publishing events asynchronously.

  This callback returns a Task that can be awaited for the result.
  """
  @callback publish_async(event :: struct()) :: Task.t()

  @doc """
  Callback for publishing events asynchronously with options or timeout.

  This callback returns a Task that can be awaited for the result.
  """
  @callback publish_async(
              event :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: Task.t()

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_publish_requests__ do
        @registered_publish_requests
        |> Enum.map(fn {request_module, _opts} -> request_module end)
        |> Enum.uniq()
      end

      @registered_publish_requests_by_module Enum.group_by(
                                               @registered_publish_requests,
                                               fn {request_module, _opts} -> request_module end,
                                               fn {_request_module, opts} -> opts end
                                             )

      @doc false
      def publish_async(event, opts \\ [])

      @doc false
      def publish_async(event, :infinity), do: do_publish_async(event, timeout: :infinity)

      @doc false
      def publish_async(event, timeout) when is_integer(timeout),
        do: do_publish_async(event, timeout: timeout)

      @doc false
      def publish_async(event, opts), do: do_publish_async(event, opts)

      defp do_publish_async(event, opts) do
        Task.Supervisor.async_nolink(
          @task_supervisor,
          __MODULE__,
          :publish,
          [event, opts],
          timeout: Keyword.fetch!(opts, :timeout)
        )
      end

      @doc false
      def publish(event, opts \\ [])

      @doc false
      def publish(event, :infinity), do: do_publish(event, timeout: :infinity)

      @doc false
      def publish(event, timeout) when is_integer(timeout),
        do: do_publish(event, timeout: timeout)

      @doc false
      def publish(event, opts), do: do_publish(event, opts)

      for {event_module, event_opts} <- @registered_publish_requests_by_module do
        @event_module event_module
        @event_opts Enum.map(event_opts, fn opts ->
                      Keyword.put(opts, :middleware, @registered_publish_middleware)
                    end)

        defp do_publish(%@event_module{} = event, opts) do
          opts = Keyword.merge(@default_publish_dispatch_opts, opts)

          concurrency_timeout = Keyword.get(opts, :concurrency_timeout)
          max_concurrency = Keyword.get(opts, :max_concurrency, 1)

          resp =
            do_batch_dispatch(event, @event_opts, opts, max_concurrency, concurrency_timeout)

          resp =
            resp
            |> Enum.filter(fn item -> publish_errors?(item) end)
            |> Enum.map(fn item -> elem(item, 1) end)

          if Enum.empty?(resp) do
            :ok
          else
            {:error, resp}
          end
        end
      end

      defp do_publish(_event, _opts), do: :ok

      defp publish_errors?(:ok), do: false
      defp publish_errors?({:ok, _resp}), do: false
      defp publish_errors?(_resp), do: true

      defp do_batch_dispatch(event, ming_opts, user_opts, 1, _concurrency_timeout) do
        Enum.map(ming_opts, fn opts -> do_dispatch(event, opts, user_opts) end)
      end

      defp do_batch_dispatch(event, ming_opts, user_opts, max_concurrency, concurrency_timeout) do
        Task.async_stream(
          ming_opts,
          fn opts -> do_dispatch(event, opts, user_opts) end,
          max_concurrency: max_concurrency,
          timeout: concurrency_timeout
        )
      end

      defp do_dispatch(request, ming_opts, opts) do
        alias Ming.Dispatcher
        alias Ming.Dispatcher.Payload

        handler = Keyword.fetch!(ming_opts, :to)
        function = Keyword.fetch!(ming_opts, :function)
        before_execute = Keyword.fetch!(ming_opts, :before_execute)
        middlewares = Keyword.fetch!(ming_opts, :middleware)

        opts = Keyword.merge(ming_opts, opts)

        application = Keyword.fetch!(opts, :application)
        request_uuid = Keyword.get_lazy(opts, :request_uuid, &UUIDv7.generate/0)
        correlation_id = Keyword.get_lazy(opts, :correlation_id, &UUIDv7.generate/0)
        metadata = Keyword.fetch!(opts, :metadata) |> validate_publish_metadata()
        retry_attempts = Keyword.get(opts, :retry_attempts)
        timeout = Keyword.fetch!(opts, :timeout)
        returning = Keyword.get(opts, :returning)

        payload = %Payload{
          application: application,
          request: request,
          request_uuid: request_uuid,
          correlation_id: correlation_id,
          metadata: metadata,
          timeout: timeout,
          retry_attempts: retry_attempts,
          handler_module: handler,
          handler_function: function,
          handler_before_execute: before_execute,
          middleware: middlewares,
          returning: returning
        }

        Dispatcher.dispatch(payload)
      end

      defp validate_publish_metadata(value) when is_map(value), do: value

      defp validate_publish_metadata(_),
        do: raise(ArgumentError, message: "metadata must be an map")
    end
  end

  @register_publish_params [
    :to,
    :function,
    :before_execute,
    :timeout
  ]

  defp parse_publish_opts([{:to, handler} | opts], result) do
    parse_publish_opts(opts, [function: :execute, to: handler] ++ result)
  end

  defp parse_publish_opts([{param, value} | opts], result)
       when param in @register_publish_params do
    parse_publish_opts(opts, [{param, value} | result])
  end

  defp parse_publish_opts([{param, _value} | _opts], _result) do
    raise """
    unexpected dispatch parameter "#{param}"
    available params are: #{Enum.map_join(@register_publish_params, ", ", &to_string/1)}
    """
  end

  defp parse_publish_opts([], result), do: result
end
