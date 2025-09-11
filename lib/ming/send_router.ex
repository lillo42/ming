defmodule Ming.SendRouter do
  require Logger
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

      Module.register_attribute(__MODULE__, :registered_send_requests, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_send_middleware, accumulate: true)

      @default_send_dispatch_opts [
        application: unquote(otp_app),
        timeout: unquote(timeout),
        metadata: %{},
        retry_attempts: unquote(retry_attempts),
        before_execute: nil,
        returning: false
      ]
    end
  end

  defmacro send_middleware(middleware_module) do
    quote do
      @registered_send_middleware unquote(middleware_module)
    end
  end

  defmacro send_dispatch(request_module_or_modules, opts) do
    opts = parse_send_opts(opts, [])

    for request_module <- List.wrap(request_module_or_modules) do
      quote do
        @registered_send_requests {
          unquote(request_module),
          Keyword.merge(@default_send_dispatch_opts, unquote(opts))
        }
      end
    end
  end

  @type send_resp ::
          :ok
          | {:ok, any()}
          | {:error, :unregistered_command}
          | {:error, :more_than_one_handler_found}
          | {:error, any()}

  @callback send(command :: struct()) :: send_resp()

  @callback send(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: send_resp()

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_send_requests__ do
        @registered_send_requests
        |> Enum.map(fn {request_module, _opts} -> request_module end)
        |> Enum.uniq()
      end

      @registered_send_requests_by_module Enum.group_by(
                                            @registered_send_requests,
                                            fn {request_module, _opts} -> request_module end,
                                            fn {_request_module, opts} -> opts end
                                          )

      @doc false
      def send(command, opts \\ [])

      @doc false
      def send(command, :infinity), do: do_send(command, timeout: :infinity)

      @doc false
      def send(command, timeout) when is_integer(timeout), do: do_send(command, timeout: timeout)

      @doc false
      def send(command, opts), do: do_send(command, opts)

      for {command_module, command_opts} <- @registered_send_requests_by_module do
        @command_module command_module

        if Enum.count(command_opts) == 1 do
          @command_opts Enum.at(command_opts, 0)
                        |> Keyword.put(:middleware, @registered_send_middleware)

          defp do_send(%@command_module{} = request, opts) do
            alias Ming.Dispatcher
            alias Ming.Dispatcher.Payload

            ming_opts = @command_opts

            handler = Keyword.fetch!(ming_opts, :to)
            function = Keyword.fetch!(ming_opts, :function)
            before_execute = Keyword.fetch!(ming_opts, :before_execute)
            middlewares = Keyword.fetch!(ming_opts, :middleware)

            opts = Keyword.merge(ming_opts, opts)

            application = Keyword.fetch!(opts, :application)
            request_uuid = Keyword.get_lazy(opts, :request_uuid, &UUIDV7.generate/0)
            correlation_id = Keyword.get_lazy(opts, :correlation_id, &UUIDV7.generate/0)
            metadata = Keyword.fetch!(opts, :metadata) |> validate_send_metadata()
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
        else
          defp do_send(%@command_module{}, _opts) do
            {:error, :more_than_one_handler_found}
          end
        end
      end

      defp do_send(command, opts) do
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
          "attempted to dispatch an unregistered request: " <> inspect(command)
        end)

        Telemetry.stop(
          event_prefix,
          start_time,
          Map.put(telemetry_metadata, :error, :unregistered_command)
        )

        {:error, :unregistered_command}
      end

      defp validate_send_metadata(value) when is_map(value), do: value
      defp validate_send_metadata(_), do: raise(ArgumentError, message: "metadata must be an map")
    end
  end

  @register_send_params [
    :to,
    :function,
    :before_execute,
    :timeout
  ]

  defp parse_send_opts([{:to, handler} | opts], result) do
    parse_send_opts(opts, [function: :execute, to: handler] ++ result)
  end

  defp parse_send_opts([{param, value} | opts], result) when param in @register_send_params do
    parse_send_opts(opts, [{param, value} | result])
  end

  defp parse_send_opts([{param, _value} | _opts], _result) do
    raise """
    unexpected dispatch parameter "#{param}"
    available params are: #{Enum.map_join(@register_send_params, ", ", &to_string/1)}
    """
  end

  defp parse_send_opts([], result), do: result
end
