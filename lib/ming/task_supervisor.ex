defmodule Ming.TaskSupervisor do
  @moduledoc """
  A `DynamicSupervisor` used to supervise asynchronous tasks spawned by Ming routers.

  This module is the default task supervisor for `publish_async/2` operations in
  `Ming.PublishRouter` and `Ming.PublishCompositeRouter`. It can be replaced with a
  custom supervisor via the `:task_supervisor` option when using a router.

  ## Usage

  Add the supervisor to your application supervision tree:

      children = [
        Ming.TaskSupervisor
      ]

  Or start it manually:

      DynamicSupervisor.start_link(strategy: :one_for_one, name: Ming.TaskSupervisor)

  ## Configuration

  Override the default supervisor in a router:

      use Ming.PublishRouter,
        otp_app: :my_app,
        task_supervisor: MyApp.TaskSupervisor
  """

  use DynamicSupervisor

  @doc """
  Starts the task supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
