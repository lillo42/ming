defmodule Ming.Router do
  @moduledoc """
  Provides a unified routing interface that combines both command sending and event publishing capabilities.

  This module serves as a convenience wrapper that combines `Ming.SendRouter`, `Ming.PublishRouter` and `Ming.QueryRouter`
  functionality into a single module. It allows you to define both command and event routing in one place,
  with shared configuration and middleware.

  ## Key Features
  - Unified interface for both command sending, event publishing and executing query
  - Shared middleware configuration for both command, event and query pipelines
  - Combined command and event registration
  - Consistent configuration across both routing types
  - Aggregate request registration for both commands and events

  ## Usage

  Use this module to create a comprehensive router that handles both commands and events:

      defmodule MyApp.Router do
        use Ming.Router,
          ming: :my_app,
          timeout: 10_000,
          retry_attempts: 5,
          max_concurrency: 8,
          concurrency_timeout: 30_000

        # Middleware applied to both commands and events
        middleware MyApp.AuthMiddleware
        middleware MyApp.LoggingMiddleware

        middleware MyApp.MetricsMiddleware

        # Register commands (sent to single handler)
        dispatch CreateUser, to: UserHandler
        dispatch UpdateUser, to: UserHandler

        # Register events (published to multiple handlers)  
        dispatch OrderCreated, to: OrderProjection
        dispatch OrderCreated, to: EmailNotifier
        dispatch OrderCreated, to: AnalyticsService

      end

  Then you can use the same router for both commands and events:

      # Send a command
      MyApp.Router.send(%CreateUser{name: "John", email: "john@example.com"})

      # Publish an event
      MyApp.Router.publish(%OrderCreated{order_id: "123", amount: 100.0})
  """
  require Ming.QueryRouter

  @doc """
  Sets up the combined Router module with configuration options.

  This macro is invoked when using `Ming.Router` in another module.
  It sets up both SendRouter and PublishRouter functionality with shared configuration.

  ## Options
  - `:ming` - The OTP application name (required)
  - `:timeout` - Default timeout for both command and event processing in milliseconds (default: `5000`)
  - `:retry` - Default number of retry attempts for failed operations (default: `10`)
  - `:concurrency_timeout` - Timeout for concurrent event processing (default: `30000`)
  - `:max_concurrency` - Maximum number of concurrent event handlers (default: `1`)
  - `:task_supervisor` - Task supervisor for async operations (default: `Ming.TaskSupervisor`)

  ## Examples
      use Ming.Router,
        ming: :my_app,
        timeout: 15_000,
        retry: 3,
        max_concurrency: 5,
        concurrency_timeout: 45_000
  """
  defmacro __using__(opts) do
    app = Keyword.get(opts, :ming)
    timeout = Keyword.get(opts, :timeout, 5_000)
    retry_attempts = Keyword.get(opts, :retry, 10)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 30_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.SendRouter,
        otp_app: unquote(app),
        timeout: unquote(timeout),
        retry_attempts: unquote(retry_attempts)

      use Ming.PublishRouter,
        otp_app: unquote(app),
        timeout: unquote(timeout),
        retry_attempts: unquote(retry_attempts),
        concurrency_timeout: unquote(concurrency_timeout),
        max_concurrency: unquote(max_concurrency),
        task_supervisor: unquote(task_supervisor)

      use Ming.QueryRouter,
        otp_app: unquote(app),
        timeout: unquote(timeout),
        retry_attempts: unquote(retry_attempts)
    end
  end

  @doc """
  Registers middleware for both command and event processing pipelines.

  This macro applies the specified middleware to both the SendRouter and PublishRouter,
  ensuring consistent cross-cutting concerns across both command and event processing.

  ## Parameters
  - `middleware_module` - The middleware module to register for both pipelines

  ## Examples
      middleware MyApp.AuthMiddleware
      middleware MyApp.LoggingMiddleware
      middleware MyApp.ValidationMiddleware


  ## Note
  The middleware module must implement both the `Ming.Middleware` behaviour for command
  processing and the appropriate interfaces for event processing.
  """
  defmacro middleware(middleware_module) do
    quote do
      send_middleware(unquote(middleware_module))
      publish_middleware(unquote(middleware_module))
      query_middleware(unquote(middleware_module))
    end
  end

  @doc """
  Registers a request for both command sending, event publishing and query execution.

  This macro registers the specified request module with both the SendRouter and PublishRouter,
  allowing it to be used for both command execution and event publication.

  ## Parameters
  - `request_module_or_modules` - A single request module or list of request modules
  - `opts` - Configuration options for both command and event dispatch

  ## Options
  - `:to` - The handler module that will process the request (required)
  - `:function` - The handler function to call (default: `:execute`)
  - `:before_execute` - Optional function to prepare the request before execution
  - `:timeout` - Timeout for this specific request (overrides default)
  - `:metadata` - Additional metadata for the execution context
  - `:retry_attempts` - Number of retry attempts for this request
  - `:returning` - Specifies what should be returned from execution

  ## Examples
      # Single request to single handler (command behavior)
      dispatch CreateUser, to: UserHandler

      # Single request to multiple handlers (event behavior)
      dispatch OrderCreated, to: OrderProjection
      dispatch OrderCreated, to: EmailNotifier

      # Multiple requests to same handler
      dispatch [CreateUser, UpdateUser, DeleteUser], to: UserHandler

      # With custom options
      dispatch ProcessPayment,
        to: PaymentHandler,
        function: :handle_payment,
        timeout: 30_000,
        metadata: %{priority: "high"}
  """
  defmacro dispatch(request_module_or_modules, opts) do
    quote do
      Ming.SendRouter.send(unquote(request_module_or_modules), unquote(opts))
      Ming.PublishRouter.publish(unquote(request_module_or_modules), unquote(opts))
      Ming.QueryRouter.query(unquote(request_module_or_modules), unquote(opts))
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_requests__ do
        requests =
          __registered_send_requests__() ++
            __registered_publish_requests__() ++
            __registered_query_requests__()

        Enum.uniq(requests)
      end
    end
  end
end
