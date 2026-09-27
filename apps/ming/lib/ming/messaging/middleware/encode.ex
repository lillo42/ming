defmodule Ming.Messaging.Middleware.Encode do
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

  def execute(context, _args, next) do
    next.(context)
  end

  defp to_message(%Context{} = context, mapper) do
    {mapper, opts} = Mapper.resolve(mapper)

    case mapper.to_message(context.request, context, Keyword.get(opts, :args)) do
      %Message{} = message ->
        %Context{context | request: message}
        |> Context.assign(:request, context.request)

      {:ok, %Message{} = message} ->
        %Context{context | request: message}
        |> Context.assign(:request, context.request)

      %Context{request: %Message{}} = new_context ->
        new_context
        |> Context.assign(:request, context.request)

      %Context{} ->
        context
        |> Context.respond({:error, "invalid response"})

      {:error, reason} ->
        context
        |> Context.respond({:error, reason})
    end
  end

  # The transformer behaviour/runner does not exist yet; pass the message
  # through unchanged until Ming.Messaging.Transformer lands.
  defp apply_transformers(%Context{} = context, _transformers), do: context
end
