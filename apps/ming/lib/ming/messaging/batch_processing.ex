defmodule Ming.Messaging.BatchProcessing do
  @moduledoc """
  Behaviour and shared logic for batch processing strategies.

  A batch processing strategy receives the batch of messages a
  `Ming.Messaging.Pump` polled from a consumer and processes each one:
  dispatching it through the dispatcher's consume pipeline and settling it
  (ack, nack or defer) according to the result.

  ## Callback arguments

  `execute/2` receives the batch and a keyword list with:

    * `:consumer` — module implementing `Ming.Messaging.Consumer`, used to
      settle each message (required)
    * `:subscription` — the subscription config map, carrying
      `:routing_key`, `:name`, `:on_error`, `:message_processing_timeout`
      and `:batch_processing_timeout` (required)
    * `:dispatcher` — the dispatcher module messages are sent through
      (required)

  Strategy-specific options are merged into the same list.

  ## Settlement

  The pipeline response settles the message:

    * `:ack` — ack (also the default for any other successful response)
    * `:nack` — nack
    * `{:defer, delay}` — defer for `delay` milliseconds
    * `{:error, reason}` — handled by the `:on_error` policy

  Handlers may also raise `Ming.DeferError` or `Ming.NackError` to settle
  without returning an action. Any other exception, throw or exit is passed
  to the `:on_error` policy — a `(message, error) -> action` function on the
  subscription, defaulting to `{:defer, 5_000}`. If applying that action
  fails, the message is nacked so it is always settled.
  """

  alias Ming.Messaging.Message

  require Logger

  @doc """
  Processes a batch of messages for a subscription.
  """
  @callback execute(messages :: [Message.t()], args :: keyword()) :: :ok

  @doc """
  Resolves a batch processing strategy reference into a `{module, args}` tuple.
  """
  @spec resolve(:sequential | :parallel | module() | {module(), keyword()}) ::
          {module(), keyword()}
  def resolve(:sequential), do: {Ming.Messaging.BatchProcessing.Sequential, []}
  def resolve(:parallel), do: {Ming.Messaging.BatchProcessing.Parallel, []}
  def resolve({module, args}), do: {module, args}
  def resolve(module) when is_atom(module), do: {module, []}

  @doc """
  Dispatches a single message through the dispatcher and settles it.

  Shared by all strategies; see the module documentation for the settlement
  rules. `deadline` (a monotonic timestamp in milliseconds, or `nil`) caps
  the per-message timeout together with the subscription's
  `:message_processing_timeout`.
  """
  @spec process_message(Message.t(), keyword(), integer() | nil) :: :ok | {:error, any()}
  def process_message(message, args, deadline \\ nil) do
    subscription = Keyword.fetch!(args, :subscription)
    dispatcher = Keyword.fetch!(args, :dispatcher)

    timeout = message_timeout(subscription, deadline)

    try do
      message
      |> dispatch(dispatcher, subscription, timeout)
      |> normalize_response()
      |> case do
        {:error, reason} -> settle_error(message, reason, args)
        action -> apply_action(action, message, args)
      end
    rescue
      error in Ming.DeferError -> apply_action({:defer, error.delay}, message, args)
      _error in Ming.NackError -> apply_action(:nack, message, args)
      error -> settle_error(message, error, args)
    catch
      kind, reason -> settle_error(message, {kind, reason}, args)
    end
  end

  @doc """
  Computes the deadline for a batch timeout in monotonic milliseconds.
  """
  @spec deadline(timeout() | nil) :: integer() | nil
  def deadline(nil), do: nil
  def deadline(:infinity), do: nil
  def deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp dispatch(message, dispatcher, subscription, timeout) do
    dispatcher.send(message,
      routing_key: subscription[:routing_key],
      id: message.id,
      correlation_id: message.correlation_id,
      timeout: timeout,
      metadata: %{
        original_message: message,
        subscription: subscription,
        mapper: subscription[:mapper]
      }
    )
  end

  defp normalize_response(:ack), do: :ack
  defp normalize_response(:nack), do: :nack
  defp normalize_response({:defer, delay}), do: {:defer, delay}
  defp normalize_response({:error, _reason} = error), do: error
  defp normalize_response(_response), do: :ack

  defp apply_action(action, message, args) do
    consumer = Keyword.fetch!(args, :consumer)
    subscription = Keyword.fetch!(args, :subscription)

    case action do
      :ack -> consumer.ack(subscription, message)
      :nack -> consumer.nack(subscription, message)
      {:defer, delay} -> consumer.defer(subscription, message, delay)
    end
  end

  defp settle_error(message, error, args) do
    subscription = Keyword.fetch!(args, :subscription)
    on_error = subscription[:on_error] || (&default_on_error/2)

    try do
      message
      |> on_error.(error)
      |> normalize_response()
      |> apply_action(message, args)
    rescue
      error_action_error ->
        # The error action itself failed; fall back to a nack so the message
        # is always settled rather than left unacked.
        Logger.error(
          "the error action of subscription #{subscription[:name]} failed " <>
            "(#{Exception.message(error_action_error)}); the message is nacked instead"
        )

        apply_action(:nack, message, args)
    end
  end

  defp default_on_error(_message, _error), do: {:defer, 5_000}

  defp message_timeout(subscription, deadline) do
    processing_timeout = subscription[:message_processing_timeout] || :infinity

    case remaining(deadline) do
      nil -> processing_timeout
      remaining -> min_timeout(processing_timeout, remaining)
    end
  end

  defp remaining(nil), do: nil
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp min_timeout(:infinity, timeout), do: timeout
  defp min_timeout(left, right), do: min(left, right)
end
