defmodule Ming.CommandProcessor do
  defmacro __using__(opts) do
    app = Keyword.fetch!(opts, :otp_app)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 5_000)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)
    dispatch_opts = Keyword.get(opts, :dispatch_opts, [])

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.CompositeRouter,
        otp_app: unquote(app),
        max_concurrency: unquote(max_concurrency),
        concurrency_timeout: unquote(concurrency_timeout),
        task_supervisor: unquote(task_supervisor),
        default_send_dispatch_opts: unquote(dispatch_opts),
        default_publish_dispatch_opts: unquote(dispatch_opts)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
    end
  end
end
