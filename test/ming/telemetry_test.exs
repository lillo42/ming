defmodule Ming.TelemetryTest do
  use ExUnit.Case

  alias Ming.Telemetry

  describe "start/3" do
    test "emits start event and returns start time" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:test, :event, :start]])

      start_time = Telemetry.start([:test, :event], %{key: "value"})

      assert is_integer(start_time)

      assert_received {[:test, :event, :start], ^ref, measurements, %{key: "value"}}
      assert Map.has_key?(measurements, :system_time)

      :telemetry.detach(ref)
    end
  end

  describe "stop/4" do
    test "emits stop event with duration" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:test, :event, :stop]])

      start_time = System.monotonic_time()
      Telemetry.stop([:test, :event], start_time, %{key: "value"})

      assert_received {[:test, :event, :stop], ^ref, measurements, %{key: "value"}}
      assert Map.has_key?(measurements, :duration)
      assert measurements.duration >= 0

      :telemetry.detach(ref)
    end
  end

  describe "exception/7" do
    test "emits exception event with kind, reason, stacktrace" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:test, :event, :exception]])

      start_time = System.monotonic_time()

      Telemetry.exception(
        [:test, :event],
        start_time,
        :error,
        %RuntimeError{message: "oops"},
        [],
        %{key: "value"}
      )

      assert_received {[:test, :event, :exception], ^ref, measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert metadata.kind == :error
      assert metadata.reason == %RuntimeError{message: "oops"}
      assert metadata.stacktrace == []

      :telemetry.detach(ref)
    end
  end
end
