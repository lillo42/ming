defmodule Ming.QueryRouter do
  alias Ming.Dispatcher.Payload
  alias Ming.Telemetry

  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    timeout = Keyword.get(opts, :timeout, 5_000)
    retry_attempts = Keyword.get(opts, :retry, 10)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_query, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_query_middleware, accumulate: true)

      @default_query_opts [
        application: unquote(otp_app),
        timeout: unquote(timeout),
        metadata: %{},
        retry_attempts: unquote(retry_attempts),
        before_execute: nil,
        returning: false
      ]
    end
  end

  defmacro query_middleware(middleware_module) do
    quote do
      @registered_query_middleware unquote(middleware_module)
    end
  end

  defmacro query(request_module_or_modules, opts) do
    opts = parse_query_opts(opts, [])

    for request_module <- List.wrap(request_module_or_modules) do
      quote do
        @registered_query {
          unquote(request_module),
          Keyword.merge(@default_query_opts, unquote(opts))
        }
      end
    end
  end

  @type query_resp ::
          any()
          | {:ok, any()}
          | {:error, :unregistered_query}
          | {:error, :more_than_one_handler_found}
          | {:error, any()}

  @callback query(query :: struct()) :: query_resp()

  @callback query(
              query :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: query_resp()

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_query_requests__ do
        @registered_query
        |> Enum.map(fn {request_module, _opts} -> request_module end)
        |> Enum.uniq()
      end

      @registered_requests_by_module Enum.group_by(
                                       @registered_query,
                                       fn {request_module, _opts} -> request_module end,
                                       fn {_request_module, opts} -> opts end
                                     )

      @doc false
      def query(query, opts \\ [])

      @doc false
      def query(query, :infinity), do: do_query(query, timeout: :infinity)

      @doc false
      def query(query, timeout) when is_integer(timeout),
        do: do_query(query, timeout: timeout)

      @doc false
      def query(query, opts), do: do_query(query, opts)

      for {query_module, query_opts} <- @registered_requests_by_module do
        @query_module query_module

        if Enum.count(query_opts) == 1 do
          @query_opts Enum.at(query_opts, 0)
                      |> Keyword.put(:middleware, @registered_query_middleware)

          defp do_query(%@query_module{} = request, opts) do
            alias Ming.Dispatcher
            alias Ming.Dispatcher.Payload

            ming_opts = @query_opts

            handler = Keyword.fetch!(ming_opts, :to)
            function = Keyword.fetch!(ming_opts, :function)
            before_execute = Keyword.fetch!(ming_opts, :before_execute)
            middlewares = Keyword.fetch!(ming_opts, :middleware)

            opts = Keyword.merge(ming_opts, opts)

            application = Keyword.fetch!(opts, :application)
            request_uuid = Keyword.get_lazy(opts, :request_uuid, &UUIDv7.generate/0)
            correlation_id = Keyword.get_lazy(opts, :correlation_id, &UUIDv7.generate/0)
            metadata = Keyword.fetch!(opts, :metadata) |> validate_query_metadata()
            retry_attempts = Keyword.get(opts, :retry_attempts)
            timeout = Keyword.fetch!(opts, :timeout)

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
              returning: :events
            }

            Dispatcher.dispatch(payload)
          end
        else
          defp do_query(%@query_module{}, _opts) do
            {:error, :more_than_one_handler_found}
          end
        end
      end

      defp do_query(command, opts) do
        event_prefix = [:ming, :application, :dispatch]
        application = Keyword.fetch!(opts, :application)

        context = %Ming.ExecutionContext{
          request: command
        }

        telemetry_metadata = %{
          application: application,
          error: nil,
          execution_context: context
        }

        start_time = Telemetry.start(event_prefix, telemetry_metadata)

        Logger.error(fn ->
          "attempted to dispatch an unregistered query: " <> inspect(command)
        end)

        Telemetry.stop(
          event_prefix,
          start_time,
          Map.put(telemetry_metadata, :error, :unregistered_command)
        )

        {:error, :unregistered_query}
      end

      defp validate_query_metadata(value) when is_map(value), do: value

      defp validate_query_metadata(_),
        do: raise(ArgumentError, message: "metadata must be an map")
    end
  end

  @register_query_params [
    :to,
    :function,
    :before_execute,
    :timeout
  ]

  defp parse_query_opts([{:to, handler} | opts], result) do
    parse_query_opts(opts, [function: :execute, to: handler] ++ result)
  end

  defp parse_query_opts([{param, value} | opts], result) when param in @register_query_params do
    parse_query_opts(opts, [{param, value} | result])
  end

  defp parse_query_opts([{param, _value} | _opts], _result) do
    raise """
    unexpected dispatch parameter "#{param}"
    available params are: #{Enum.map_join(@register_query_params, ", ", &to_string/1)}
    """
  end

  defp parse_query_opts([], result), do: result
end
