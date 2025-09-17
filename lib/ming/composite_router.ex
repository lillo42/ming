defmodule Ming.CompositeRouter do
  @moduledoc """
  Provides a comprehensive composite routing system that aggregates both Send and Publish composite routers.

  This module serves as the highest-level routing abstraction in the Ming framework, combining
  both `Ming.SendCompositeRouter` and `Ming.PublishCompositeRouter` functionality into a single
  unified interface. It allows you to create a master router that aggregates multiple sub-routers
  of both types (command and event routers).

  ## Key Features
  - Unified aggregation of both command and event composite routers
  - Shared configuration with override capabilities for send vs publish operations
  - Simplified inclusion of both command and event routers with a single macro
  - Configurable concurrency settings for event processing
  - Centralized management of all routing in a large application

  ## Usage
  Use this module to create a master composite router that combines multiple sub-routers:

      defmodule MyApp.MasterRouter do
        use Ming.CompositeRouter,
          otp_app: :my_app,
          max_concurrency: 10,
          concurrency_timeout: 60_000,
          default_dispatch_opts: [timeout: 15_000, metadata: %{source: "master"}],
          default_send_opts: [timeout: 10_000, retry_attempts: 3],
          default_publish_opts: [timeout: 20_000, max_concurrency: 5]

        # Include both command and event routers from different domains
        router MyApp.Accounting.Router
        router MyApp.Inventory.Router

        router MyApp.Shipping.Router
        router MyApp.Analytics.Router
      end

  Then you can use the master router for both commands and events across all domains:

      # Send commands through the composite
      MyApp.MasterRouter.send(%CreateInvoice{...})
      MyApp.MasterRouter.send(%UpdateInventory{...})

      # Publish events through the composite  
      MyApp.MasterRouter.publish(%OrderCreated{...})
      MyApp.MasterRouter.publish_async(%PaymentProcessed{...})
  """

  @doc """
  Sets up the CompositeRouter module with configuration options.

  This macro is invoked when using `Ming.CompositeRouter` in another module.
  It sets up both SendCompositeRouter and PublishCompositeRouter functionality
  with shared and specific configuration options.

  ## Options
  - `:otp_app` - The OTP application name (default: `:ming`)
  - `:max_concurrency` - Maximum number of concurrent event publications (default: `1`)
  - `:concurrency_timeout` - Timeout for concurrent publishing operations (default: `5000`)
  - `:task_supervisor` - Task supervisor for async operations (default: `Ming.TaskSupervisor`)
  - `:default_dispatch_opts` - Default options applied to both send and publish operations
  - `:default_send_opts` - Specific default options for send operations (overrides dispatch opts)
  - `:default_publish_opts` - Specific default options for publish operations (overrides dispatch opts)

  ## Examples
      use Ming.CompositeRouter,
        otp_app: :my_app,
        max_concurrency: 8,
        concurrency_timeout: 30_000,
        default_dispatch_opts: [timeout: 15_000],
        default_send_opts: [retry_attempts: 5],
        default_publish_opts: [max_concurrency: 3]
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    default_dispatch_opts = Keyword.get(opts, :default_dispatch_opts, [])

    default_send_opts =
      case Keyword.get(opts, :default_send_opts, []) do
        [] ->
          default_dispatch_opts

        send_opts ->
          send_opts
      end

    default_publish_opts =
      case Keyword.get(opts, :default_publish_opts, []) do
        [] ->
          default_dispatch_opts

        publish_opts ->
          publish_opts
      end

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.SendCompositeRouter,
        otp_app: unquote(otp_app),
        default_send_opts: unquote(default_send_opts)

      use Ming.PublishCompositeRouter,
        otp_app: unquote(otp_app),
        default_publish_opts: unquote(default_publish_opts),
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout),
        task_supervisor: unquote(task_supervisor)
    end
  end

  @doc """
  Includes a router module in both the Send and Publish composite routers.

  This macro registers the specified router module with both the SendCompositeRouter
  and PublishCompositeRouter, making all its commands and events available through
  the master composite interface.

  ## Parameters
  - `router_module` - The router module to include in both composites

  ## Examples
      router MyApp.Accounting.Router
      router MyApp.Inventory.Router
      router MyApp.Shipping.Router

  ## Note
  The included router module should implement both `__registered_send_requests__/0`
  and `__registered_publish_requests__/0` functions to be properly integrated.
  """
  defmacro router(router_module) do
    quote do
      send_router(unquote(router_module))
      publish_router(unquote(router_module))
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      # Empty implementation - this hook is available for future extensions
      # while maintaining the @before_compile behavior that users might expect
    end
  end
end
