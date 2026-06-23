defmodule Ming.Context do
  @type t :: %__MODULE__{}

  @enforce_keys [:request, :routing_key, :timeout]

  defstruct [
    :correlation_id,
    :handler,
    :metadata,
    :request,
    :response,
    :routing_key,
    :timeout,
    :timestamp,
    assigns: %{},
    halted?: false,
    middlewares: []
  ]

  def assign(%__MODULE__{assigns: assigns} = context, key, value),
    do: %__MODULE__{context | assigns: Map.put(assigns, key, value)}

  def halted?(%__MODULE__{halted?: halted?}), do: halted?

  def halt(%__MODULE__{halted?: false} = context), do: %__MODULE__{context | halted?: true}
  def halt(%__MODULE__{} = context), do: context

  def response(%__MODULE__{response: response}), do: response

  def respond(%__MODULE__{} = context, respond), do: %__MODULE__{context | response: respond}
end
