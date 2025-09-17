defmodule Ming.PublishCompositeRouter do
  @moduledoc """
  Provides a composite routing system that aggregates multiple PublishRouters in the Ming framework.

  This module allows you to combine multiple `Ming.PublishRouter` modules into a single composite
  router, providing a unified interface for publishing events across different domains or

  bounded contexts within your application.

  ## Key Features
  - Aggregates multiple PublishRouter modules into a single publishing interface
  - Provides unified event publishing across different application domains
  - Handles concurrent event publishing to multiple routers with configurable concurrency
  - Maintains the same API as individual PublishRouter modules
  - Aggregates errors from multiple routers for comprehensive error reporting

  ## Usage

  Use this module to create a composite router that combines multiple domain-specific event routers:

      defmodule MyApp.CompositePublishRouter do
        use Ming.PublishCompositeRouter, 
          otp_app: :my_app,
          max_concurrency: 10,
          concurrency_timeout: 60_000

        # Include event routers from different bounded contexts
        publish_router MyApp.Accounting.PublishRouter
        publish_router MyApp.Inventory.PublishRouter  
        publish_router MyApp.Shipping.PublishRouter
        publish_router MyApp.Analytics.PublishRouter
      end

  Then you can publish events to any registered router through the composite interface:

      MyApp.CompositePublishRouter.publish(%UserCreated{...})
      MyApp.CompositePublishRouter.publish_async(%OrderPlaced{...})
  """
  alias Ming.PublishRouter

  @doc """
  Sets up the PublishCompositeRouter module with configuration options.

  This macro is invoked when using `Ming.PublishCompositeRouter` in another module.
  It registers module attributes and sets default configuration values for composite event publishing.

  ## Options
  - `:otp_app` - The OTP application name (default: `:ming`)
  - `:max_concurrency` - Maximum number of concurrent router publications (default: `1`)
  - `:concurrency_timeout` - Timeout for concurrent publishing operations (default: `5000`)
  - `:task_supervisor` - Task supervisor for async operations (default: `Ming.TaskSupervisor`)
  - `:default_publish_dispatch_opts` - Default options for event dispatch

  ## Examples
      use Ming.PublishCompositeRouter,
        otp_app: :my_app,
        max_concurrency: 5,
        concurrency_timeout: 30_000,
        default_publish_dispatch_opts: [timeout: 15_000, metadata: %{source: "composite"}]
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)

    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_events, accumulate: true)

      default_publish_dispatch_opts =
        unquote(opts)
        |> Keyword.get(:default_publish_dispatch_opts, [])
        |> Keyword.put(:application, unquote(otp_app))

      @default_publish_dispatch_opts default_publish_dispatch_opts

      @task_supervisor unquote(task_supervisor)

      @composite_router_opts [
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout)
      ]
    end
  end

  @doc """
  Includes a PublishRouter module in the composite router.

  This macro registers all events from the specified PublishRouter module,
  making them available through the composite router interface.

  ## Parameters
  - `router_module` - The `Ming.PublishRouter` module to include in the composite

  ## Examples
      publish_router MyApp.Accounting.PublishRouter
      publish_router MyApp.Inventory.PublishRouter

  ## Note
  The included router module must implement the `__registered_publish_requests__/0`
  function which returns a list of registered event modules.
  """
  defmacro publish_router(router_module) do
    quote do
      if Kernel.function_exported?(unquote(router_module), :__registered_publish_requests__, 0) do
        for event_module <- unquote(router_module).__registered_publish_requests__() do
          @registered_events {event_module, unquote(router_module)}
        end
      end
    end
  end

  @doc """
  Callback for publishing events through the composite router.

  This callback provides a consistent interface for event publishing that
  matches individual PublishRouter modules.
  """
  @callback publish(event :: struct()) :: PublishRouter.publish_resp()

  @doc """
  Callback for publishing events with options or timeout through the composite router.

  This callback provides a consistent interface for event publishing with additional
  configuration options that matches individual PublishRouter modules.
  """
  @callback publish(
              event :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: PublishRouter.publish_resp()

  @doc """
  Callback for publishing events asynchronously through the composite router.

  This callback returns a Task that can be awaited for the result.
  """
  @callback publish_async(event :: struct()) :: Task.t()

  @doc """
  Callback for publishing events asynchronously with options through the composite router.

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
        @registered_events
        |> Enum.map(fn {event_module, _router} -> event_module end)
        |> Enum.uniq()
      end

      @doc false
      def publish_async(event, opts \\ [])

      @doc false
      def publish_async(event, :infinity), do: do_publish_async(event, timeout: :infinity)

      @doc false
      def publish_async(event, timeout) when is_integer(timeout),
        do: do_publish_async(event, timeout: timeout)

      @doc false
      def publish_async(event, opts), do: do_publish_async(event, opts)

      @doc false
      def publish(event, opts \\ [])

      @doc false
      def publish(event, :infinity), do: do_publish(event, timeout: :infinity)

      @doc false
      def publish(event, timeout) when is_integer(timeout),
        do: do_publish(event, timeout: timeout)

      @doc false
      def publish(event, opts), do: do_publish(event, opts)

      @registered_events_by_module Enum.group_by(
                                     @registered_events,
                                     fn {request_module, _router_module} -> request_module end,
                                     fn {_request_module, router_module} -> router_module end
                                   )

      for {event_module, router_modules} <- @registered_events_by_module do
        @event_module event_module
        @router_modules router_modules

        defp do_publish(%@event_module{} = event, opts) do
          opts = Keyword.merge(@default_publish_dispatch_opts, opts)

          max_concurrency = Keyword.get(@composite_router_opts, :max_concurrency)
          concurrency_timeout = Keyword.fetch!(@composite_router_opts, :concurrency_timeout)

          resp =
            do_batch_publish(event, opts, @router_modules, max_concurrency, concurrency_timeout)
            |> Stream.filter(fn item -> publish_errors?(item) end)
            |> Stream.map(fn item -> elem(item, 1) end)
            |> Stream.flat_map(fn item -> item end)
            |> Enum.to_list()

          if Enum.empty?(resp) do
            :ok
          else
            {:error, resp}
          end
        end
      end

      defp do_publish(_event, _opts) do
        :ok
      end

      defp do_publish_async(event, opts) do
        Task.Supervisor.async_nolink(@task_supervisor, fn -> publish(event, opts) end)
      end

      defp do_batch_publish(event, opts, router_modules, 1, _concurrency_timeout) do
        Enum.map(router_modules, fn router -> router.publish(event, opts) end)
      end

      defp do_batch_publish(event, opts, router_modules, max_concurrency, concurrency_timeout) do
        Task.async_stream(
          router_modules,
          fn router -> router.publish(event, opts) end,
          ordered: false,
          max_concurrency: max_concurrency,
          timeout: concurrency_timeout
        )
      end

      defp publish_errors?({:error, _resp}), do: true
      defp publish_errors?(_resp), do: false
    end
  end
end
