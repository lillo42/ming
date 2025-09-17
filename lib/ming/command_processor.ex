defmodule Ming.CommandProcessor do
  @moduledoc """
  Provides a high-level command processing interface built on top of Ming's composite routing system.

  This module serves as the primary entry point for command processing in the Ming framework,
  wrapping the `Ming.CompositeRouter` with simplified configuration and sensible defaults
  optimized for command processing scenarios.

  ## Key Features
  - Simplified configuration for command processing applications
  - Unified interface for both command sending and event publishing
  - Built-in concurrency control for event processing
  - Sensible defaults optimized for command processing workloads
  - Easy integration with existing CompositeRouter infrastructure

  ## Usage
  Use this module to create a command processor for your application:

      defmodule MyApp.CommandProcessor do
        use Ming.CommandProcessor,

          otp_app: :my_app,
          max_concurrency: 4,
          concurrency_timeout: 30_000,

          dispatch_opts: [timeout: 15_000, retry_attempts: 3]

        # Include domain routers that contain command handlers
        router MyApp.Accounting.Router

        router MyApp.Inventory.Router
        router MyApp.Shipping.Router
      end

  Then use the command processor to send commands and publish events:

      # Send commands
      MyApp.CommandProcessor.send(%CreateUser{name: "John", email: "john@example.com"})

      # Publish events (e.g., from aggregate roots)
      MyApp.CommandProcessor.publish(%UserCreated{id: 123, name: "John"})

  ## Design Philosophy

  The CommandProcessor is designed as the top-level abstraction for CQRS applications,
  providing a simple yet powerful interface that hides the complexity of the underlying
  routing system while exposing all necessary functionality.
  """

  @doc """
  Sets up the CommandProcessor module with optimized configuration for command processing.

  This macro is invoked when using `Ming.CommandProcessor` in another module.
  It configures the underlying `Ming.CompositeRouter` with defaults optimized
  for command processing scenarios.

  ## Options
  - `:otp_app` - The OTP application name (required)
  - `:max_concurrency` - Maximum number of concurrent event publications (default: `1`)
  - `:concurrency_timeout` - Timeout for concurrent publishing operations (default: `5000`)
  - `:task_supervisor` - Task supervisor for async operations (default: `Ming.TaskSupervisor`)
  - `:dispatch_opts` - Default options applied to both send and publish operations

  ## Required Options
  - `:otp_app` - Must be provided and cannot be defaulted


  ## Examples
      use Ming.CommandProcessor,
        otp_app: :my_app,
        max_concurrency: 2,
        concurrency_timeout: 15_000,
        dispatch_opts: [timeout: 10_000, retry_attempts: 2]

  ## Note
  Unlike `Ming.CompositeRouter`, this module uses a single `:dispatch_opts` parameter
  that applies to both send and publish operations, simplifying configuration for
  command processing scenarios where consistent behavior is desired.
  """
  defmacro __using__(opts) do
    app = Keyword.fetch!(opts, :otp_app)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)
    dispatch_opts = Keyword.get(opts, :dispatch_opts, [])

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.CompositeRouter,
        otp_app: unquote(app),
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout),
        task_supervisor: unquote(task_supervisor),
        default_send_opts: unquote(dispatch_opts),
        default_publish_opts: unquote(dispatch_opts)
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      # Empty implementation - maintains compatibility with the @before_compile behavior
      # while providing a hook for future extensions specific to command processing
    end
  end
end
