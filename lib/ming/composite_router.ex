defmodule Ming.CompositeRouter do
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    default_dispatch_opts = Keyword.get(opts, :default_dispatch_opts, [])

    default_send_opts =
      case Keyword.get(opts, :default_send_opts, []) do
        [] ->
          default_dispatch_opts

        send_opts ->
          send_opts
      end

    default_publish_opts =
      case Keyword.get(opts, :default_publish_opts, []) do
        [] ->
          default_dispatch_opts

        publish_opts ->
          publish_opts
      end

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.SendCompositeRouter,
        otp_app: unquote(otp_app),
        default_send_opts: unquote(default_send_opts)

      use Ming.PublishCompositeRouter,
        otp_app: unquote(otp_app),
        default_publish_opts: unquote(default_publish_opts),
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout),
        task_supervisor: unquote(task_supervisor)
    end
  end

  defmacro router(router_module) do
    quote do
      send_router(unquote(router_module))
      publish_router(unquote(router_module))
    end
  end

  defmacro __before_compile__(_env) do
    quote do
    end
  end
end
