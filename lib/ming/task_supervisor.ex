defmodule Ming.TaskSupervisor do
  use DynamicSupervisor

  def init(initial) do
    {:ok, initial}
  end
end
