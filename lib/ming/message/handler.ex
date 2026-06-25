defmodule Ming.Message.Handler do
  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Handler

  @impl Ming.Handler
  def handle(
        %Message{} = request,
        %Context{
          assigns:
            %{
              ming_message_producer: producer,
              ming_message_publication: publication
            } = assigns
        }
      ) do
    producer.send(request, publication, Map.get(assigns, :ming_message_opts, []))
  end
end
