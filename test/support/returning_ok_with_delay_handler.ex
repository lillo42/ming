defmodule Ming.ReturningOkWithDelayHandler do
  def execute(%Ming.ExampleCommand1{} = command, _context) do
    :timer.sleep(command.value)
    :ok
  end

  def execute(%Ming.ExampleEvent1{} = event, _context) do
    :timer.sleep(event.value)
    :ok
  end
end
