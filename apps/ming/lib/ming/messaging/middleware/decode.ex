defmodule Ming.Messaging.Middleware.Decode do
  @behaviour Ming.Middleware

  alias Ming.Context
  alias Ming.Messaging.Mapper
  alias Ming.Messaging.Message

  @impl Ming.Middleware
  def execute(
        %Context{
          request: %Message{},
          metadata: %{ming_mapper: mapper, ming_subscription: subscription}
        } = context,
        _args,
        next
      ) do
    context =
      context
      |> apply_transformers(Map.get(subscription, :transformers, []))
      |> to_request(mapper)

    case context do
      %Context{response: nil} -> next.(context)
      _halted_with_error -> context
    end
  end

  def execute(context, _args, next), do: next.(context)

  defp to_request(%Context{} = context, mapper) do
    {mapper, opts} = Mapper.resolve(mapper)

    case mapper.to_request(context.request, context, opts) do
      {:ok, request} ->
        %Context{context | request: request}

      %Context{} = new_context ->
        new_context

      {:error, reason} ->
        context
        |> Context.respond({:error, reason})

      request ->
        %Context{context | request: request}
    end
  end

  defp apply_transformers(context, []), do: context

  defp apply_transformers(%Context{} = context, [{transformer, args} | transformers]) do
    case transformer.decode(context.request, args, context) do
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

      %Context{} ->
        context
        |> Context.respond({:error, "invalid response"})
    end
  end
end
