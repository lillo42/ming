defmodule TestKafkaProcessor do
  @moduledoc """
  Test command processor that sends consumed messages back to the test process.

  The target pid is read from `:ming` application env `:kafka_test_target_pid`.
  The response returned to the consumer is read from `:ming` application env
  `:kafka_test_response` and defaults to `{:ok, :ack}`.
  """

  import Kernel, except: [send: 2]

  def send(message, opts) do
    pid = Application.fetch_env!(:ming, :kafka_test_target_pid)
    Kernel.send(pid, {:consumed, message, opts})

    Application.get_env(:ming, :kafka_test_response, {:ok, :ack})
  end
end
