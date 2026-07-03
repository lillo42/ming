defmodule Ming.Gateway.RetryConfigTest do
  use ExUnit.Case

  alias Ming.Gateway.RetryConfig

  describe "new/1" do
    test "uses default values when no options are given" do
      config = RetryConfig.new()

      assert config.max_retries == 5
      assert config.base_delay == 1_000
      assert config.max_delay == 30_000
      assert config.backoff_type == :rand_exp
    end

    test "overrides defaults with provided options" do
      config = RetryConfig.new(max_retries: 10, base_delay: 500, backoff_type: :linear)

      assert config.max_retries == 10
      assert config.base_delay == 500
      assert config.backoff_type == :linear
    end
  end

  describe "calculate_delay/2" do
    test "fixed backoff always returns the base delay" do
      config = RetryConfig.new(base_delay: 1_000, backoff_type: :fixed)

      assert RetryConfig.calculate_delay(config, 0) == 1_000
      assert RetryConfig.calculate_delay(config, 5) == 1_000
    end

    test "linear backoff increases with each attempt" do
      config = RetryConfig.new(base_delay: 1_000, backoff_type: :linear)

      assert RetryConfig.calculate_delay(config, 0) == 1_000
      assert RetryConfig.calculate_delay(config, 2) == 3_000
    end

    test "exponential backoff doubles with each attempt" do
      config = RetryConfig.new(base_delay: 1_000, backoff_type: :exp)

      assert RetryConfig.calculate_delay(config, 0) == 1_000
      assert RetryConfig.calculate_delay(config, 1) == 2_000
      assert RetryConfig.calculate_delay(config, 2) == 4_000
    end

    test "randomized exponential backoff stays within expected bounds" do
      config = RetryConfig.new(base_delay: 1_000, backoff_type: :rand_exp)

      delay = RetryConfig.calculate_delay(config, 2)
      # Expected base is 4000; randomized result is between base/2 and base.
      assert delay >= 2_000 and delay <= 4_000
    end

    test "respects the maximum delay cap" do
      config = RetryConfig.new(base_delay: 1_000, max_delay: 3_000, backoff_type: :exp)

      assert RetryConfig.calculate_delay(config, 10) == 3_000
    end
  end
end
