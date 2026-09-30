defmodule Ming.Messaging.Transformer.GzipCompression do
  @behaviour Ming.Messaging.Transformer

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Messaging.Transformer
  def encode(%Message{} = message, args, %Context{}) do
    should_compress = Keyword.get(args, :should_compress, fn _m -> true end)

    if should_compress.(message) do
      %Message{
        message
        | content_encoding: "gz",
          payload: :zlib.gzip(message.payload)
      }
    else
      message
    end
  end

  @impl Ming.Messaging.Transformer
  def decode(%Message{} = message, args, %Context{}) do
    should_uncompress =
      Keyword.get(args, :should_uncompress, fn m -> m.content_encoding == "gz" end)

    if should_uncompress.(message) do
      %Message{message | payload: :zlib.unzip(message.payload)}
    else
      message
    end
  end
end
