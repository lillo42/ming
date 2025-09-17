defmodule Ming.QueryCompositeRouter do
  @moduledoc """
  Provides a composite routing system that aggregates multiple QueryRouters in the Ming framework.

  This module allows you to combine multiple `Ming.QueryRouter` modules into a single composite

  router, providing a unified interface for query execution across different domains or
  bounded contexts within your application.

  ## Key Features
  - Aggregates multiple QueryRouter modules into a single query interface
  - Provides unified query execution across different application domains
  - Handles query routing conflicts between different routers
  - Maintains the same API as individual QueryRouter modules
  - Simplified configuration with default options inheritance

  ## Usage
  Use this module to create a composite query router that combines multiple domain-specific query routers:

      defmodule MyApp.CompositeQueryRouter do
        use Ming.QueryCompositeRouter, 

          otp_app: :my_app,
          default_query_opts: [timeout: 10_000, metadata: %{source: "composite"}]

        # Include query routers from different bounded contexts

        query_router MyApp.Accounting.QueryRouter
        query_router MyApp.Inventory.QueryRouter  
        query_router MyApp.Customer.QueryRouter
        query_router MyApp.Reporting.QueryRouter
      end

  Then you can execute queries through the composite interface:

      MyApp.CompositeQueryRouter.query(%GetUserById{id: 123})
      MyApp.CompositeQueryRouter.query(%GetProductInventory{product_id: "456"})

  ## Design Philosophy

  The QueryCompositeRouter follows the same pattern as other composite routers in Ming,
  providing a unified facade for multiple query routers while maintaining the simplicity
  of the individual query router API.
  """

  @doc """
  Sets up the QueryCompositeRouter module with configuration options.

  This macro is invoked when using `Ming.QueryCompositeRouter` in another module.
  It registers module attributes and sets default configuration values for composite query routing.

  ## Options
  - `:otp_app` - The OTP application name (default: `:ming`)
  - `:default_query_opts` - Default options applied to all query operations

  ## Examples
      use Ming.QueryCompositeRouter,
        otp_app: :my_app,
        default_query_opts: [timeout: 15_000, metadata: %{environment: "production"}]
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_query, accumulate: true)

      default_query_opts =
        unquote(opts)
        |> Keyword.get(:default_query_opts, [])
        |> Keyword.put(:application, unquote(otp_app))

      @default_query_opts default_query_opts
    end
  end

  @doc """
  Includes a QueryRouter module in the composite router.

  This macro registers all queries from the specified QueryRouter module,

  making them available through the composite router interface.

  ## Parameters
  - `router_module` - The `Ming.QueryRouter` module to include in the composite

  ## Examples
      query_router MyApp.Accounting.QueryRouter
      query_router MyApp.Inventory.QueryRouter

  ## Note
  The included router module must implement the `__registered_query_requests__/0`
  function which returns a list of registered query modules.
  """
  defmacro query_router(router_module) do
    quote do
      for command_module <- unquote(router_module).__registered_query_requests__() do
        @registered_query {command_module, unquote(router_module)}
      end
    end
  end

  @doc """
  Callback for executing queries through the composite router.

  This callback provides a consistent interface for query execution that
  matches individual QueryRouter modules.
  """
  @callback query(query :: struct()) :: Ming.QueryRouter.query_resp()

  @doc """
  Callback for executing queries with options or timeout through the composite router.

  This callback provides a consistent interface for query execution with additional
  configuration options that matches individual QueryRouter modules.
  """
  @callback query(
              query :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: Ming.QueryRouter.query_resp()

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_query_requests__ do
        @registered_query
        |> Enum.map(fn {query_module, _router} -> query_module end)
        |> Enum.uniq()
      end

      @doc false
      def query(query, opts \\ [])

      @doc false
      def query(query, :infinity), do: do_query(query, timeout: :infinity)

      @doc false
      def query(query, timeout) when is_integer(timeout), do: do_query(query, timeout: timeout)

      @doc false
      def query(query, opts), do: do_query(query, opts)

      @registered_query_by_module Enum.group_by(
                                    @registered_query,
                                    fn {query_module, _router_module} -> query_module end,
                                    fn {_request_module, router_module} -> router_module end
                                  )
      for {query_module, router_modules} <- @registered_query_by_module do
        @query_module query_module
        if Enum.count(router_modules) == 1 do
          @router Enum.at(router_modules, 0)

          defp do_query(%@query_module{} = command, opts) do
            opts = Keyword.merge(@default_query_opts, opts)

            @router.send(command, opts)
          end
        else
          defp do_query(%@query_module{} = command, opts) do
            {:error, :more_than_one_handler_found}
          end
        end
      end

      defp do_query(command, _opts) do
        {:error, :unregistered_query}
      end
    end
  end
end
