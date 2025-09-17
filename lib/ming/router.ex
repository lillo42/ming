defmodule Ming.Router do
  defmacro __using__(opts) do
    app = Keyword.get(opts, :ming)
    timeout = Keyword.get(opts, :timeout, 5_000)
    retry_attempts = Keyword.get(opts, :retry, 10)
    concurrency_timeout = Keyword.get(opts, :concurrency_timeout, 30_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.SendRouter,
        otp_app: unquote(app),
        timeout: unquote(timeout),
        retry_attempts: unquote(retry_attempts)

      use Ming.PublishRouter,
        otp_app: unquote(app),
        timeout: unquote(timeout),
        retry_attempts: unquote(retry_attempts),
        concurrency_timeout: unquote(concurrency_timeout),
        max_concurrency: unquote(max_concurrency),
        task_supervisor: unquote(task_supervisor)
    end
  end

  defmacro middleware(middleware_module) do
    quote do
      send_middleware(unquote(middleware_module))
      publish_middleware(unquote(middleware_module))
    end
  end

  defmacro dispatch(request_module_or_modules, opts) do
    quote do
      send(unquote(request_module_or_modules), unquote(opts))
      publish(unquote(request_module_or_modules), unquote(opts))
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      def __registered_requests__ do
        requests = __registered_send_requests__() ++ __registered_publish_requests__()
        Enum.uniq(requests)
      end
    end
  end
end
