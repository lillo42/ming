defmodule Ming.CommandProcessor do
  @moduledoc """
  Command Process
  """

  @doc false
  defmacro __using__(opts) do
    app = Keyword.fetch!(opts, :otp_app)
    task_supervisor = Keyword.get(opts, :task_supervisor, Ming.TaskSupervisor)
    dispatch_opts = Keyword.get(opts, :dispatch_opts, [])

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Ming.CompositeRouter,
        otp_app: unquote(app),
        default_dispatch_opts: unquote(dispatch_opts)

      @otp_app unquote(app)
      @task_supervisor unquote(task_supervisor)
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      def publish_async(event, opts \\ [])

      def publish_async(event, :infinity), do: do_publish_async(event, timeout: :infinity)

      def publish_async(event, timeout) when is_number(timeout),
        do: do_publish_async(event, timeout: timeout)

      def publish_async(event, opts), do: do_publish_async(event, opts)

      defp do_publish_async(event, opts) do
        Task.Supervisor.async_nolink(
          @task_supervisor,
          __MODULE__,
          :publish,
          [event, opts],
          timeout: Keyword.fetch!(opts, :timeout)
        )
      end
    end
  end
end
