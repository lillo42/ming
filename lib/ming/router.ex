defmodule Ming.Router do
  @moduledoc """
  Command routing macro to allow configuration of each command to its command handler.


  ## Example

  Define a router module which uses `Ming.Router` and configures
  available request to dispatch:


      defmodule BankRouter do
        use Ming.Router


        dispatch OpenAccount,
          to: OpenAccountHandler,
      end

  The `to` option determines which module receives the request being dispatched.

  This command handler module must implement a `handle/1` function. It receives
  the command to execute.

  Once configured, you can either dispatch a request by using the module and

  specifying the application:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.send(command, application: BankApp)


  Or, more simply, you should include the router module in your application:

      defmodule CommandProcssor do
        use Ming.CommandProcssor , otp_app: :my_app

        router MyApp.Router
      end

  Then dispatch commands using the app:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankApp.send(command)

  Alternatively, you may specify the name of a function on your handle module to which the command will be dispatched:

  ### Example

      defmodule BankRouter do
        use Commanded.Commands.Router


        # Will route to `BankAccount.open_account/2`
        dispatch OpenAccount, to: BankAccount, function: :open_account 
      end


  ## Metadata

  You can associate metadata with all events created by the command.

  Supply a map containing key/value pairs comprising the metadata:

      :ok = BankApp.send(command, metadata: %{"ip_address" => "127.0.0.1"})

  """
  require Logger
  alias Ming.Dispatcher.Payload
  alias Ming.Telemetry
  alias Ming.UUID

  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    timeout = Keyword.get(opts, :timeout, 5_000)
    retry_attempts = Keyword.get(opts, :retry, 10)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 30_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_send_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_publish_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_post_middleware, accumulate: true)

      @default_dispatch_opts [
        application: unquote(otp_app),
        timeout: unquote(timeout),
        metadata: %{},
        retry_attempts: unquote(retry_attempts),
        concurrency_timeout: unquote(concurrency_timeout),
        max_concurrency: unquote(max_concurrency),
        before_execute: nil,
        returning: false
      ]
    end
  end

  @doc """

  Include the given middleware module to be called before and after
  success or failure of each command dispatch(send/publish/post)

  The middleware module must implement the `Ming.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Ming.Router

        middleware CommandLogger
        middleware MyCommandValidator
        middleware AuthorizeCommand

        dispatch [OpenAccount, DepositMoney], to: BankAccount
      end


  """
  defmacro middleware(middleware_module) do
    quote do
      @registered_send_middleware unquote(middleware_module)
      @registered_publish_middleware unquote(middleware_module)
      @registered_post_middleware unquote(middleware_module)
    end
  end

  @doc """

  Include the given middleware module to be called before and after
  success or failure of each message dispatch using send

  The middleware module must implement the `Ming.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Ming.Router

        send_middleware CommandLogger
        send_middleware MyCommandValidator
        send_middleware AuthorizeCommand

        dispatch [OpenAccount, DepositMoney], to: BankAccount
      end


  """
  defmacro send_middleware(middleware_module) do
    quote do
      @registered_send_middleware unquote(middleware_module)
    end
  end

  @doc """

  Include the given middleware module to be called before and after
  success or failure of each message dispatch using publish

  The middleware module must implement the `Ming.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Ming.Router

        publish_middleware CommandLogger
        publish_middleware MyCommandValidator
        publish_middleware AuthorizeCommand

        dispatch [OpenAccount, DepositMoney], to: BankAccount
      end


  """
  defmacro publish_middleware(middleware_module) do
    quote do
      @registered_publish_middleware unquote(middleware_module)
    end
  end

  @doc """

  Include the given middleware module to be called before and after
  success or failure of each message dispatch using post 

  The middleware module must implement the `Ming.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Ming.Router

        post_middleware CommandLogger
        post_middleware MyCommandValidator
        post_middleware AuthorizeCommand

        dispatch [OpenAccount, DepositMoney], to: BankAccount
      end


  """
  defmacro post_middleware(middleware_module) do
    quote do
      @registered_post_middleware unquote(middleware_module)
    end
  end

  @doc """
  Configure the command, or list of commands, to be dispatched to the
  corresponding handler.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch [OpenAccount, DepositMoney], to: BankAccount
      end

  """
  defmacro dispatch(command_module_or_modules, opts) do
    opts = parse_opts(opts, [])

    for command_module <- List.wrap(command_module_or_modules) do
      quote do
        @registered_commands {
          unquote(command_module),
          Keyword.merge(@default_dispatch_opts, unquote(opts))
        }
      end
    end
  end

  @type send_resp ::
          :ok
          | {:ok, any()}
          | {:error, :unregistered_command}
          | {:error, :more_than_one_handler_founded}
          | {:error, term()}

  @doc """

  Dispatch the given command to one registered handler.

  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
      :ok = BankRouter.send(command)

  """
  @callback send(command :: struct()) :: send_resp()

  @doc """

  Dispatch the given command to one registered handler.

    - `command` is a command struct which must be registered with the router.

    - `timeout_or_opts` is either an integer timeout, `:infinity`, or a keyword
      list of options.

      The timeout must be an integer greater than zero which specifies how many
      milliseconds to allow the command to be handled, or the atom `:infinity`
      to wait indefinitely. The default timeout value is five seconds.


      Alternatively, an options keyword list can be provided with the following
      options.

      Options:

        - `request_uuid` - an optional UUID used to identify the command being
          dispatched.

        - `correlation_id` - an optional UUID used to correlate related
          commands/events together.

        - `metadata` - an optional map containing key/value pairs comprising
          the metadata to be associated with all events created by the
          command.

       - `timeout` - as described above.

  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.send(command, consistency: :strong, timeout: 30_000)

  """
  @callback send(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: send_resp()

  @type publish_resp ::
          :ok
          | {:error, term()}
          | {:error, [term()]}

  @doc """

  Dispatch the given event to all registered handler.

  Returns `:ok` or `{:ok, any()}` on success, or `{:error, reason}` on failure.

  ## Example

      event = %AccountOpened{account_number: "ACC123", initial_balance: 1_000}
      :ok = BankRouter.publish(event)

  """
  @callback publish(event :: struct()) :: publish_resp()

  @doc """

  Dispatch the given command to all registered handler.

    - `command` is a command struct which must be registered with the router.

    - `timeout_or_opts` is either an integer timeout, `:infinity`, or a keyword
      list of options.

      The timeout must be an integer greater than zero which specifies how many
      milliseconds to allow the command to be handled, or the atom `:infinity`
      to wait indefinitely. The default timeout value is five seconds.


      Alternatively, an options keyword list can be provided with the following
      options.

      Options:

        - `request_uuid` - an optional UUID used to identify the command being
          dispatched.

        - `correlation_id` - an optional UUID used to correlate related
          commands/events together.

        - `metadata` - an optional map containing key/value pairs comprising
          the metadata to be associated with all events created by the
          command.

       - `timeout` - as described above.

       - `concurrency_timeout` - the maximum amount of time (in milliseconds or :infinity) each task is allowed to execute for. Defaults to 30_000 

       - `max_concurrency` - sets the maximum number of tasks to run at the same time. Defaults to`System.schedulers_online/0`.

  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.send(command, consistency: :strong, timeout: 30_000)

  """
  @callback publish(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: publish_resp()

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_commands__ do
        @registered_commands
        |> Enum.map(fn {command_module, _opts} -> command_module end)
        |> Enum.uniq()
      end

      @doc false
      def send(command, opts \\ [])

      @doc false
      def send(command, :infinity),
        do: do_dispatch(command, :send, timeout: :infinity)

      @doc false
      def send(command, timeout) when is_integer(timeout),
        do: do_dispatch(command, :send, timeout: timeout)

      @doc false
      def send(command, opts),
        do: do_dispatch(command, :send, opts)

      @doc false
      def publish(event, opts \\ [])

      @doc false
      def publish(event, :infinity),
        do: do_dispatch(event, :publish, timeout: :infinity)

      @doc false
      def publish(event, timeout) when is_integer(timeout),
        do: do_dispatch(event, :publish, timeout: timeout)

      @doc false
      def publish(event, opts),
        do: do_dispatch(event, :publish, opts)

      for {command_module, opts} <-
            Enum.group_by(
              @registered_commands,
              fn {command_module, _opts} -> command_module end,
              fn {_command_module, opts} -> opts end
            ) do
        @request_module command_module

        if Enum.count(opts) == 1 do
          @request_opts Enum.at(opts, 0)

          defp do_dispatch(%@request_module{} = command, :send, opts) do
            do_dispatch(
              command,
              Keyword.put(@request_opts, :middleware, @registered_send_middleware),
              opts
            )
          end

          defp do_dispatch(%@request_module{} = event, :publish, opts) do
            case do_dispatch(
                   event,
                   Keyword.put(@request_opts, :middleware, @registered_publish_middleware),
                   opts
                 ) do
              :ok ->
                :ok

              {:ok, _resp} ->
                :ok

              {:error, reason} ->
                {:error, [reason]}
            end
          end
        else
          @request_opts opts

          defp do_dispatch(%@request_module{}, :send, _opts) do
            {:error, :more_than_one_handler_founded}
          end

          defp do_dispatch(%@request_module{} = event, :publish, opts) do
            opts = Keyword.merge(@default_dispatch_opts, opts)

            concurrency_timeout = Keyword.get(opts, :concurrency_timeout)
            max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

            resp =
              if max_concurrency == 1 do
                Enum.map(
                  @request_opts,
                  fn request_opts ->
                    do_dispatch(
                      event,
                      Keyword.put(request_opts, :middleware, @registered_publish_middleware),
                      opts
                    )
                  end
                )
              else
                Task.async_stream(
                  @request_opts,
                  fn request_opts ->
                    do_dispatch(
                      event,
                      Keyword.put(request_opts, :middleware, @registered_publish_middleware),
                      opts
                    )
                  end,
                  max_concurrency: max_concurrency,
                  timeout: concurrency_timeout
                )
              end

            resp =
              resp
              |> Enum.filter(fn item -> errors?(item) end)
              |> Enum.map(fn item -> elem(item, 1) end)

            if Enum.empty?(resp) do
              :ok
            else
              {:error, resp}
            end
          end
        end
      end

      # Catch unregistered request, log and return an error.
      defp do_dispatch(command, :send, opts) do
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

      defp do_dispatch(request, :publish, opts) do
        :ok
      end

      defp do_dispatch(request, default_opts, opts) do
        alias Ming.Dispatcher
        alias Ming.Dispatcher.Payload

        handler = Keyword.fetch!(default_opts, :to)
        function = Keyword.fetch!(default_opts, :function)
        before_execute = Keyword.fetch!(default_opts, :before_execute)
        middlewares = Keyword.fetch!(default_opts, :middleware)

        opts = Keyword.merge(default_opts, opts)

        application = Keyword.fetch!(opts, :application)
        request_uuid = Keyword.get_lazy(opts, :request_uuid, &UUID.uuid4/0)
        correlation_id = Keyword.get_lazy(opts, :correlation_id, &UUID.uuid4/0)
        metadata = Keyword.fetch!(opts, :metadata) |> validate_metadata()
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

      defp errors?(:ok), do: false
      defp errors?({:ok, _resp}), do: false
      defp errors?(_resp), do: true

      # Make sure the metadata must be Map.t()
      defp validate_metadata(value) when is_map(value), do: value
      defp validate_metadata(_), do: raise(ArgumentError, message: "metadata must be an map")
    end
  end

  @register_params [
    :to,
    :function,
    :before_execute,
    :timeout
  ]

  defp parse_opts([{:to, handler} | opts], result) do
    parse_opts(opts, [function: :execute, to: handler] ++ result)
  end

  defp parse_opts([{param, value} | opts], result) when param in @register_params do
    parse_opts(opts, [{param, value} | result])
  end

  defp parse_opts([{param, _value} | _opts], _result) do
    raise """
    unexpected dispatch parameter "#{param}"
    available params are: #{Enum.map_join(@register_params, ", ", &to_string/1)}
    """
  end

  defp parse_opts([], result), do: result
end
