defmodule Ming.InMemoryProducer do
  @behaviour Ming.MessageProducer

  def send_with_delay(message, _delay, publication, config) do
    send(message, publication, config)
  end

  def send(_message, _publication, _config) do
    :ok
  end
end
