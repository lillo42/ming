defmodule TestAMQPProcessor do
  @moduledoc """
  Test command processor that sends consumed messages back to the test process.

  The target pid is read from `:ming` application env `:amqp_test_target_pid`.
  """

  import Kernel, except: [send: 2]

  def send(message, opts) do
    pid = Application.fetch_env!(:ming, :amqp_test_target_pid)
    Kernel.send(pid, {:consumed, message, opts})
    {:ok, :ack}
  end
end
