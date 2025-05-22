defmodule Ming.CompositeRouter do
  @moduledoc """
  Composite router allows you to combine multiple router modules into a single
  router able to dispatch any registered command from an included child router.

  One example usage is to define a router per context and then combine each
  context's router into a single top-level composite app router used for all
  command dispatching.


  ### Example

  Define a composite router module which imports the commands from each included

  router:


      defmodule Bank.Router do
        use Ming.CompositeRouter

        router(Bank.Accounts.Router)
        router(Bank.MoneyTransfer.Router)
      end

    One or more routers or composite routers can be included in a
    `Ming.CommandProcessor` since it is also a composite router:


      defmodule BankCommandProcessor do
        use Ming.CommandProcessor


        router(Bank.Router)
      end


  You can dispatch a command via the application which will then be routed to
  the associated child router:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankApp.send(command)

  Or via the composite router itself, specifying the application:

      :ok = Bank.AppRouter.publish(command, application: BankApp)


  A composite router can include composite routers.
  """
  alias Ming.Router

  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)

    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered_requests, accumulate: true)

      default_dispatch_opts =
        unquote(opts)
        |> Keyword.get(:default_dispatch_opts, [])
        |> Keyword.put(:application, unquote(otp_app))

      @internal_dispatch_opts [
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout)
      ]

      @default_dispatch_opts default_dispatch_opts
      @registered_commands %{}
    end
  end

  @doc """
  Register a `Commanded.Commands.Router` module within this composite router.


  Will allow the composite router to dispatch any commands registered by the

  included router module. Multiple routers can be registered.
  """
  defmacro router(router_module) do
    quote location: :keep do
      for request <- unquote(router_module).__registered_requests__() do
        @registered_requests {request, unquote(router_module)}
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_requests__ do
        @registered_requests
        |> Enum.map(fn {request_module, _router} -> request_module end)
        |> Enum.uniq()
      end

      @doc """
      Dispatch a registered command.
      """
      @callback send(
                  command :: struct(),
                  timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
                ) :: Router.send_resp()

      @doc """
      Dispatch a registered event.
      """
      @callback publish(
                  event :: struct(),
                  timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
                ) :: Router.publish_resp()

      def send(command, opts \\ [])

      def send(command, :infinity),
        do: do_dispatch(command, :send, timeout: :infinity)

      def send(command, timeout) when is_integer(timeout),
        do: do_dispatch(command, :send, timeout: timeout)

      def send(command, opts),
        do: do_dispatch(command, :send, opts)

      def publish(event, opts \\ [])

      def publish(event, :infinity),
        do: do_dispatch(event, :publish, timeout: :infinity)

      def publish(event, timeout) when is_integer(timeout),
        do: do_dispatch(event, :publish, timeout: timeout)

      def publish(event, opts),
        do: do_dispatch(event, :publish, opts)

      for {request_module, routers} <-
            Enum.group_by(
              @registered_requests,
              fn {request_module, _router_module} -> request_module end,
              fn {_request_module, router_module} -> router_module end
            ) do
        @request_module request_module

        if Enum.count(routers) == 1 do
          @router Enum.at(routers, 0)

          defp do_dispatch(%@request_module{} = request, :send, opts) do
            opts = Keyword.merge(@default_dispatch_opts, opts)

            @router.send(request, opts)
          end

          defp do_dispatch(%@request_module{} = request, :publish, opts) do
            opts = Keyword.merge(@default_dispatch_opts, opts)

            @router.publish(request, opts)
          end
        else
          @routers routers

          defp do_dispatch(%@request_module{} = request, :send, opts) do
            {:error, :more_than_one_handler_founded}
          end

          defp do_dispatch(%@request_module{} = request, :publish, opts) do
            opts = Keyword.merge(@default_dispatch_opts, opts)

            max_concurrency = Keyword.get(@internal_dispatch_opts, :max_concurrency)
            concurrency_timeout = Keyword.fetch!(@internal_dispatch_opts, :concurrency_timeout)

            resp =
              if max_concurrency == 1 do
                Enum.map(@routers, fn router ->
                  router.publish(request, opts)
                end)
              else
                Task.async_stream(
                  @routers,
                  fn router ->
                    router.publish(request, opts)
                  end,
                  max_concurrency: max_concurrency,
                  timeout: concurrency_timeout
                )
              end

            resp =
              resp
              |> Enum.filter(fn item -> errors?(item) end)
              |> Enum.map(fn item -> elem(item, 1) end)
              |> Enum.flat_map(fn item -> item end)

            if Enum.empty?(resp) do
              :ok
            else
              {:error, resp}
            end
          end
        end
      end

      # Catch unregistered commands, log and return an error.
      defp do_dispatch(request, :send, _opts) do
        Logger.error(fn ->
          "attempted to dispatch an unregistered command: " <> inspect(request)
        end)

        {:error, :unregistered_command}
      end

      defp do_dispatch(_request, :publish, _opts) do
        :ok
      end

      defp errors?({:error, _resp}), do: true
      defp errors?(_resp), do: false
    end
  end
end
