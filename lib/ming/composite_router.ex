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

      @composite_router_opts [
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
    send_functions =
      quote generated: true, location: :keep do
        @doc """
        Dispatch a registered command.
        """
        @callback send(
                    command :: struct(),
                    timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
                  ) :: Router.send_resp()

        def send(command, opts \\ [])

        def send(command, :infinity) do
          do_send(command, timeout: :infinity)
        end

        def send(command, timeout) when is_integer(timeout) do
          do_send(command, timeout: timeout)
        end

        def send(command, opts) do
          do_send(command, opts)
        end

        for {command_module, router_modules} <- @registered_requests_by_module do
          @command_module command_module
          if Enum.count(router_modules) == 1 do
            @router Enum.at(router_modules, 0)

            defp do_send(%@command_module{} = request, opts) do
              opts = Keyword.merge(@default_dispatch_opts, opts)

              @router.send(request, opts)
            end
          else
            defp do_send(%@command_module{} = request, opts) do
              {:error, :more_than_one_handler_founded}
            end
          end
        end

        # Catch unregistered commands, log and return an error.
        defp do_send(request, _opts) do
          Logger.error(fn ->
            "attempted to dispatch an unregistered command: " <> inspect(request)
          end)

          {:error, :unregistered_command}
        end
      end

    publish_functions =
      quote generated: true, location: :keep do
        @doc """
        Dispatch a registered event.
        """
        @callback publish(
                    event :: struct(),
                    timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
                  ) :: Router.publish_resp()

        def publish(event, opts \\ [])

        def publish(event, :infinity) do
          do_publish(event, timeout: :infinity)
        end

        def publish(event, timeout) when is_integer(timeout) do
          do_publish(event, timeout: timeout)
        end

        def publish(event, opts) do
          do_publish(event, opts)
        end

        for {event_module, router_modules} <- @registered_requests_by_module do
          @event_module event_module
          @router_modules router_modules

          defp do_publish(%@event_module{} = event, opts) do
            opts = Keyword.merge(@default_dispatch_opts, opts)

            max_concurrency = Keyword.get(@composite_router_opts, :max_concurrency)
            concurrency_timeout = Keyword.fetch!(@composite_router_opts, :concurrency_timeout)

            resp =
              do_batch_publish(event, opts, @router_modules, max_concurrency, concurrency_timeout)
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

        defp do_publish(_event, _opts) do
          :ok
        end

        defp do_batch_publish(event, opts, router_modules, 1, _concurrency_timeout) do
          Enum.map(router_modules, fn router -> router.publish(event, opts) end)
        end

        defp do_batch_publish(event, opts, router_modules, max_concurrency, concurrency_timeout) do
          Task.async_stream(
            router_modules,
            fn router -> router.publish(event, opts) end,
            max_concurrency: max_concurrency,
            timeout: concurrency_timeout
          )
        end
      end

    quote generated: true do
      @doc false
      def __registered_requests__ do
        @registered_requests
        |> Enum.map(fn {request_module, _router} -> request_module end)
        |> Enum.uniq()
      end

      @registered_requests_by_module Enum.group_by(
                                       @registered_requests,
                                       fn {request_module, _router_module} -> request_module end,
                                       fn {_request_module, router_module} -> router_module end
                                     )

      unquote(send_functions)

      unquote(publish_functions)

      defp errors?({:error, _resp}), do: true
      defp errors?(_resp), do: false
    end
  end
end
