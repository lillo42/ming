defmodule Ming.Messaging.Middleware.Encode do
  @moduledoc """
  Encodes the pipeline request into a `%Ming.Messaging.Message{}`.

  Maps the request to a message with the mapper from the context metadata
  (`:ming_mapper`), then applies the publication's transformers in order.
  Backs the `:ming_post_message` pipeline used when a request is posted
  through the dispatcher.

  Requests that already are a `%Ming.Messaging.Message{}`, and contexts
  without `:ming_mapper` and `:ming_publication` metadata, pass through
  untouched.
  """
  @behaviour Ming.Middleware

  alias Ming.Context
  alias Ming.Messaging.Mapper
  alias Ming.Messaging.Message

  @impl Ming.Middleware
  def execute(%Context{request: %Message{}} = context, _args, next) do
    next.(context)
  end

  def execute(
        %Context{metadata: %{ming_mapper: mapper, ming_publication: publication}} = context,
        _args,
        next
      ) do
    context =
      context
      |> to_message(mapper)
      |> apply_transformers(Map.get(publication, :transformers, []))

    case context do
      %Context{response: nil} -> next.(context)
      _halted_with_error -> context
    end
  end

  def execute(context, _args, next), do: next.(context)

  defp to_message(%Context{} = context, mapper) do
    {mapper, opts} = Mapper.resolve(mapper)

    case mapper.to_message(context.request, context, Keyword.get(opts, :args)) do
      %Message{} = message ->
        %Context{context | request: message}
        |> Context.assign(:request, context.request)

      {:ok, %Message{} = message} ->
        %Context{context | request: message}
        |> Context.assign(:request, context.request)

      {:error, reason} ->
        context
        |> Context.respond({:error, reason})

      %Context{request: %Message{}} = new_context ->
        new_context
        |> Context.assign(:request, context.request)

      %Context{} ->
        context
        |> Context.respond({:error, "invalid response"})
    end
  end

  defp apply_transformers(context, []), do: context

  defp apply_transformers(%Context{} = context, [{transformer, args} | transformers]) do
    case transformer.encode(context.request, args, context) do
      %Message{} = message ->
        context = %Context{context | request: message}
        apply_transformers(context, transformers)

      {:ok, %Message{} = message} ->
        context = %Context{context | request: message}
        apply_transformers(context, transformers)

      {:error, reason} ->
        context
        |> Context.respond({:error, reason})

      %Context{request: %Message{} = _m} = new_context ->
        apply_transformers(new_context, transformers)

      %Context{} = new_context ->
        new_context
    end
  end
end
