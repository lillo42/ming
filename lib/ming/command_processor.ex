defmodule Ming.CommandProcessor do
  @moduledoc """
  Command Process
  """

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      use Commanded.Commands.CompositeRouter,
        application: __MODULE__,
        default_dispatch_opts: Keyword.get(opts, :default_dispatch_opts, [])

      @otp_app Keyword.fetch!(opts, :otp_app)
      @default_task_supervisor Keyword.get(opts, :task_supervisor)
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
        supervisor_module = @default_task_supervisor || Ming.TaskSupervisor

        Task.Supervisor.async_nolink(
          supervisor_module,
          __MODULE__,
          :publish,
          [event, opts],
          timeout: Keyword.fetch!(opts, :timeout)
        )
      end
    end
  end
end
