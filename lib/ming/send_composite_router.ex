defmodule Ming.SendCompositeRouter do
  @moduledoc """
  Provides a composite routing system that aggregates multiple SendRouters in the Ming framework.

  This module allows you to combine multiple `Ming.SendRouter` modules into a single composite
  router, providing a unified interface for sending commands across different domains or
  bounded contexts within your application.

  ## Key Features

  - Aggregates multiple SendRouter modules into a single routing interface
  - Provides unified command dispatch across different application domains
  - Handles command routing conflicts between different routers
  - Maintains the same API as individual SendRouter modules

  ## Usage

  Use this module to create a composite router that combines multiple domain-specific routers:

      defmodule MyApp.CompositeSendRouter do
        use Ming.SendCompositeRouter, otp_app: :my_app

        # Include routers from different bounded contexts
        send_router MyApp.Accounting.SendRouter
        send_router MyApp.Inventory.SendRouter  
        send_router MyApp.Shipping.SendRouter
      end

  Then you can send commands to any registered handler through the composite interface:

      MyApp.CompositeSendRouter.send(%CreateInvoice{...})
      MyApp.CompositeSendRouter.send(%UpdateInventory{...})
  """
  require Logger

  @doc """
  Sets up the SendCompositeRouter module with configuration options.

  This macro is invoked when using `Ming.SendCompositeRouter` in another module.
  It registers module attributes and sets default configuration values.

  ## Options
  - `:otp_app` - The OTP application name (default: `:ming`)
  - `:default_send_opts` - Default options for command send 

  ## Examples
      use Ming.SendCompositeRouter, 
        otp_app: :my_app,
        default_send_opts: [timeout: 10_000, retry_attempts: 3]
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_commands, accumulate: true)

      default_send_opts =
        unquote(opts)
        |> Keyword.get(:default_send_opts, [])
        |> Keyword.put(:application, unquote(otp_app))

      @default_send_opts default_send_opts
    end
  end

  @doc """
  Includes a SendRouter module in the composite router.

  This macro registers all commands from the specified SendRouter module,
  making them available through the composite router interface.

  ## Parameters
  - `router_module` - The `Ming.SendRouter` module to include in the composite

  ## Examples
      send_router MyApp.Accounting.SendRouter
      send_router MyApp.Inventory.SendRouter

  ## Note
  The included router module must implement the `__registered_send_requests__/0`
  function which returns a list of registered command modules.
  """
  defmacro send_router(router_module) do
    quote do
      # if Kernel.function_exported?(unquote(router_module), :__registered_send_requests__, 0) do
      for command_module <- unquote(router_module).__registered_send_requests__() do
        @registered_commands {command_module, unquote(router_module)}
      end

      # end
    end
  end

  @doc """
  Callback for sending commands through the composite router.

  This callback provides a consistent interface for command dispatch that
  matches individual SendRouter modules.
  """
  @callback send(command :: struct()) :: Ming.SendRouter.send_resp()

  @doc """
  Callback for sending commands with options or timeout through the composite router.

  This callback provides a consistent interface for command dispatch with additional
  configuration options that matches individual SendRouter modules.
  """
  @callback send(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: Ming.SendRouter.send_resp()

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_send_requests__ do
        @registered_commands
        |> Enum.map(fn {command_module, _router} -> command_module end)
        |> Enum.uniq()
      end

      @doc false
      def send(command, opts \\ [])

      @doc false
      def send(command, :infinity), do: do_send(command, timeout: :infinity)

      @doc false
      def send(command, timeout) when is_integer(timeout), do: do_send(command, timeout: timeout)

      @doc false
      def send(command, opts), do: do_send(command, opts)

      @registered_commands_by_module Enum.group_by(
                                       @registered_commands,
                                       fn {request_module, _router_module} -> request_module end,
                                       fn {_request_module, router_module} -> router_module end
                                     )

      for {command_module, router_modules} <- @registered_commands_by_module do
        @command_module command_module

        if Enum.count(router_modules) == 1 do
          @router Enum.at(router_modules, 0)

          defp do_send(%@command_module{} = command, opts) do
            opts = Keyword.merge(@default_send_opts, opts)

            @router.send(command, opts)
          end
        else
          defp do_send(%@command_module{} = command, opts) do
            {:error, :more_than_one_handler_found}
          end
        end
      end

      defp do_send(command, _opts) do
        {:error, :unregistered_command}
      end
    end
  end
end
