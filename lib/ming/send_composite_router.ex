defmodule Ming.SendCompositeRouter do
  require Logger

  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_commands, accumulate: true)

      default_send_dispatch_opts =
        unquote(opts)
        |> Keyword.get(:default_send_dispatch_opts, [])
        |> Keyword.put(:application, unquote(otp_app))

      @default_send_dispatch_opts default_send_dispatch_opts
    end
  end

  defmacro send_router(router_module) do
    quote do
      # if Kernel.function_exported?(unquote(router_module), :__registered_send_requests__, 0) do
      for command_module <- unquote(router_module).__registered_send_requests__() do
        @registered_commands {command_module, unquote(router_module)}
      end

      # end
    end
  end

  @callback send(command :: struct()) :: Ming.SendRouter.send_resp()

  @callback send(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: Ming.SendRouter.send_resp()

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
            opts = Keyword.merge(@default_send_dispatch_opts, opts)

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
