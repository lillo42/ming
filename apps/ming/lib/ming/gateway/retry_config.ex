defmodule Ming.Gateway.RetryConfig do
  @moduledoc """
  Configuration for retry/backoff behavior in gateway operations.

  Supports multiple backoff strategies:
  - `:rand_exp` - Randomized exponential (default): prevents thundering herd
  - `:exp` - Pure exponential backoff
  - `:linear` - Linear increase
  - `:fixed` - Fixed delay

  ## Example

      retry = RetryConfig.new(max_retries: 5, base_delay: 1_000, backoff_type: :rand_exp)
      RetryConfig.calculate_delay(retry, 0) # => ~500-1000ms
      RetryConfig.calculate_delay(retry, 1) # => ~1000-2000ms
  """

  @type backoff_type :: :rand_exp | :exp | :linear | :fixed

  @type t :: %__MODULE__{
          max_retries: non_neg_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          backoff_type: backoff_type()
        }

  defstruct [
    :max_retries,
    :base_delay,
    :max_delay,
    :backoff_type
  ]

  @default_max_retries 5
  @default_base_delay 1_000
  @default_max_delay 30_000
  @default_backoff_type :rand_exp

  @doc """
  Creates a new RetryConfig from keyword options.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay: Keyword.get(opts, :base_delay, @default_base_delay),
      max_delay: Keyword.get(opts, :max_delay, @default_max_delay),
      backoff_type: Keyword.get(opts, :backoff_type, @default_backoff_type)
    }
  end

  @doc """
  Calculates the delay for a given retry attempt.

  ## Examples

      iex> config = RetryConfig.new(base_delay: 1000, max_delay: 30_000, backoff_type: :fixed)
      iex> RetryConfig.calculate_delay(config, 0)
      1000

      iex> config = RetryConfig.new(base_delay: 1000, max_delay: 30_000, backoff_type: :linear)
      iex> RetryConfig.calculate_delay(config, 2)
      3000

      iex> config = RetryConfig.new(base_delay: 1000, max_delay: 30_000, backoff_type: :exp)
      iex> RetryConfig.calculate_delay(config, 2)
      4000
  """
  @spec calculate_delay(t(), non_neg_integer()) :: non_neg_integer()
  def calculate_delay(%__MODULE__{} = config, attempt) do
    base = min(config.base_delay * :math.pow(2, attempt), config.max_delay)

    case config.backoff_type do
      :rand_exp ->
        trunc(base / 2 + :rand.uniform_real() * base / 2)

      :exp ->
        trunc(base)

      :linear ->
        trunc(config.base_delay * (attempt + 1))

      :fixed ->
        config.base_delay
    end
  end
end
