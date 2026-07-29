defmodule FakeMapper do
  @moduledoc false

  def to_message(request, _context) do
    case FakeMapperAgent.to_message_behavior() do
      nil ->
        raise "No to_message behavior configured"

      fun ->
        fun.(request)
    end
  end

  def to_request(message, _context) do
    case FakeMapperAgent.to_request_behavior() do
      nil ->
        raise "No to_request behavior configured"

      fun ->
        fun.(message)
    end
  end
end

defmodule FakeMapperAgent do
  @moduledoc false
  use Agent

  def start_link(_),
    do: Agent.start_link(fn -> %{to_message: nil, to_request: nil} end, name: __MODULE__)

  def set_to_message(fun),
    do: Agent.update(__MODULE__, fn state -> %{state | to_message: fun} end)

  def set_to_request(fun),
    do: Agent.update(__MODULE__, fn state -> %{state | to_request: fun} end)

  def to_message_behavior, do: Agent.get(__MODULE__, fn state -> state.to_message end)
  def to_request_behavior, do: Agent.get(__MODULE__, fn state -> state.to_request end)
end

defmodule FakeProducer do
  @moduledoc false
  def publish(message, _opts) do
    FakeProducerAgent.record(message)
    :published
  end
end

defmodule FakeProducerGateway do
  @moduledoc false
  def producer, do: FakeProducer
end

defmodule FakeProducerAgent do
  @moduledoc false
  use Agent

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def record(message), do: Agent.update(__MODULE__, fn state -> [message | state] end)
  def messages, do: Agent.get(__MODULE__, fn state -> state end)
end

defmodule FakeCommandProcessor do
  @moduledoc false
  def send(request, opts) do
    FakeCommandProcessorAgent.behavior().(request, opts)
  end
end

defmodule FakeCommandProcessorAgent do
  @moduledoc false
  use Agent

  def start_link(_), do: Agent.start_link(fn -> nil end, name: __MODULE__)

  def set_behavior(fun), do: Agent.update(__MODULE__, fn _ -> fun end)
  def behavior, do: Agent.get(__MODULE__, fn state -> state end)
end
