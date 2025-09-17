defmodule Ming.QueryCompositeRouter do
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

  defmacro query_router(router_module) do
    quote do
      for command_module <- unquote(router_module).__registered_query_requests__() do
        @registered_query {command_module, unquote(router_module)}
      end
    end
  end

  @callback query(query :: struct()) :: Ming.QueryRouter.query_resp()

  @callback query(
              query :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: Ming.QueryRouter.query_resp()

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
