defmodule Ming.Router do
  alias Ming.Pipeline.Dispatcher

  defmacro __using__(opts) do
    app_module = Keyword.get(opts, :application)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)
      @behavior Router

      Module.register_attribute(__MODULE__, :registered_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_send_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_publish_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_post_middleware, accumulate: true)

      @default_dispatch_opts [
        application: unquote(app_module),
        timeout: 5_000,
        metadata: %{},
        retry_attempts: 10
      ]

      @default_send_middleware []
      @default_publish_middleware []
      @default_post_middleware []
    end
  end

  @doc """
  Include the given middleware module to be called before and after
  success or failure of each (send/publish/post) command dispatch

  The middleware module must implement the `Commanded.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

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
  success or failure of each send command dispatch

  The middleware module must implement the `Commanded.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

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
  success or failure of each publish command dispatch

  The middleware module must implement the `Commanded.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

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
  success or failure of each post command dispatch

  The middleware module must implement the `Commanded.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

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

  @type dispatch_resp :: :ok | {:error, reason :: term()}

  @doc """
  Dispatch the given command to the registered handler.

  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.dispatch(command)

  """
  @callback send(command :: struct()) :: dispatch_resp()

  @doc """
  Dispatch the given command to the registered handler providing a timeout.

    - `command` is a command struct which must be registered with the router.

    - `timeout_or_opts` is either an integer timeout, `:infinity`, or a keyword
      list of options.

      The timeout must be an integer greater than zero which specifies how many
      milliseconds to allow the command to be handled, or the atom `:infinity`
      to wait indefinitely. The default timeout value is five seconds.

      Alternatively, an options keyword list can be provided with the following
      options.


      Options:

        - `causation_id` - an optional UUID used to identify the cause of the
          command being dispatched.

        - `command_uuid` - an optional UUID used to identify the command being
          dispatched.

        - `correlation_id` - an optional UUID used to correlate related
          commands/events together.

        - `consistency` - one of `:eventual` (default) or `:strong`. By
          setting the consistency to `:strong` a successful command dispatch
          will block until all strongly consistent event handlers and process
          managers have handled all events created by the command.

        - `metadata` - an optional map containing key/value pairs comprising
          the metadata to be associated with all events created by the
          command.

        - `returning` - to choose what response is returned from a successful
            command dispatch. The default is to return an `:ok`.

            The available options are:

            - `:aggregate_state` - to return the update aggregate state in the
              successful response: `{:ok, aggregate_state}`.

            - `:aggregate_version` - to include the aggregate stream version
              in the successful response: `{:ok, aggregate_version}`.

            - `:events` - to return the resultant domain events. An empty list

              will be returned if no events were produced.


            - `:execution_result` - to return a `Commanded.Commands.ExecutionResult`
              struct containing the aggregate's identity, version, and any
              events produced from the command along with their associated
              metadata.

            - `false` - don't return anything except an `:ok`.

        - `timeout` - as described above.


  Returns `:ok` on success unless the `:returning` option is specified where
  it returns one of `{:ok, aggregate_state}`, `{:ok, aggregate_version}`, or
  `{:ok, %Commanded.Commands.ExecutionResult{}}`.

  Returns `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.send(command, consistency: :strong, timeout: 30_000)


  """
  @callback send(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: dispatch_resp()

  defmacro __before_compile__ do
    quote generated: true do
      @send_middleware Enum.reduce(
                         @registered_send_middleware,
                         @default_send_middleware,
                         fn middleware, acc ->
                           [middleware | acc]
                         end
                       )
      @doc false
      def __registered_commands__ do
        Enum.map(@registered_commands, fn {command_module, _command_opts} -> command_module end)
      end

      @doc false
      def send(command, opts \\ [])

      @doc false
      def send(command, :infinity),
        do: do_send(command, timeout: :infinity)

      @doc false
      def send(command, timeout) when is_integer(timeout),
        do: do_send(command, timeout: timeout)

      @doc false
      def send(command, opts),
        do: do_send(command, opts)

      @publish_middleware Enum.reduce(
                            @registered_publish_middleware,
                            @default_publish_middleware,
                            fn middleware, acc ->
                              [middleware | acc]
                            end
                          )

      @doc false
      def publish(command, opts \\ [])

      @doc false
      def publish(command, :infinity),
        do: do_publish(command, timeout: :infinity)

      @doc false
      def publish(command, timeout) when is_integer(timeout),
        do: do_publish(command, timeout: timeout)

      @doc false
      def publish(command, opts),
        do: do_publish(command, opts)

      @post_middleware Enum.reduce(
                         @registered_post_middleware,
                         @default_post_middleware,
                         fn middleware, acc ->
                           [middleware | acc]
                         end
                       )

      @doc false
      def post(command, opts \\ [])

      @doc false
      def post(command, :infinity),
        do: do_post(command, timeout: :infinity)

      @doc false
      def post(command, timeout) when is_integer(timeout),
        do: do_post(command, timeout: timeout)

      @doc false
      def post(command, opts),
        do: do_post(command, opts)

      for {count, config} <- Enum.group_by(@registered_commands, fn {module, _opts} -> module end) do
        @struct_module elem(Enum.at(config, 0), 0)

        def number_of_handlers(%@struct_module{}) do
          count
        end

        defp do_post() do
          :ok
        end

        cond do
          count == 0 ->
            defp do_send(%@struct_module{}, _opts) do
              {:error, :not_handler_founded}
            end

            defp do_publish(%@struct_module{}, _opts) do
              :ok
            end

          count == 1 ->
            @struct_opts Enum.at(elem(config, 1), 0)
            @handler Keyword.fetch!(@struct_opts, :to)
            @function Keyword.fetch!(@struct_opts, :function)
            @before_execute Keyword.fetch!(@struct_opts, :before_execute)

            defp do_send(%@struct_module{}, opts) do
              opts = Keyword.merge(@struct_opt, opts)
              application = Keyword.fetch!(opts, :application)
              metadata = Keyword.fetch!(opts, :metadata) |> validate_metadata()
              retry_attempts = Keyword.get(opts, :retry_attempts)
              timeout = Keyword.fetch!(opts, :timeout)

              Dispatcher.dispatch(%Ming.Pipeline.Dispatcher.Payload{
                application: application,
                metadata: metadata,
                middleware: @send_middleware,
                handler_module: @handler,
                handler_function: @function,
                handler_before_execute: @before_execute,
                timeout: timeout,
                retry_attempts: retry_attempts
              })
            end

            defp do_publish(%@struct_module{}, opts) do
              opts = Keyword.merge(@command_opts, opts)
              application = Keyword.fetch!(opts, :application)
              metadata = Keyword.fetch!(opts, :metadata) |> validate_metadata()
              retry_attempts = Keyword.get(opts, :retry_attempts)
              timeout = Keyword.fetch!(opts, :timeout)

              Dispatcher.dispatch(%Ming.Pipeline.Dispatcher.Payload{
                application: application,
                metadata: metadata,
                middleware: @publish_middleware,
                handler_module: @handler,
                handler_function: @function,
                handler_before_execute: @before_execute,
                timeout: timeout,
                retry_attempts: retry_attempts
              })
            end

          true ->
            @struct_opts Enum.map(config, fn {_module, opts} ->
                           {opts, Keyword.fetch!(opts, :to), Keyword.fetch!(opts, :function),
                            Keyword.fetch!(opts, :before_execute)}
                         end)

            defp do_send(%@struct_module{} = command, opts) do
              {:error, :more_than_one_handler_founded}
            end

            defp do_publish(%@struct_module{} = command, opts) do
              tasks =
                Enum.map(@struct_opts, fn {dispatch_opts, handler, function, before_execute} ->
                  Task.async(fn ->
                    opts = Keyword.merge(dispatch_opts, opts)
                    application = Keyword.fetch!(opts, :application)
                    metadata = Keyword.fetch!(opts, :metadata) |> validate_metadata()
                    retry_attempts = Keyword.get(opts, :retry_attempts)
                    timeout = Keyword.fetch!(opts, :timeout)

                    Dispatcher.dispatch(%Ming.Pipeline.Dispatcher.Payload{
                      application: application,
                      metadata: metadata,
                      middleware: @publish_middleware,
                      handler_module: handler,
                      handler_function: function,
                      handler_before_execute: before_execute,
                      timeout: timeout,
                      retry_attempts: retry_attempts
                    })
                  end)
                end)

              timeout = Keyword.fetch!(opts, :timeout)
              Task.await_many(tasks, timeout)
            end
        end
      end

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
