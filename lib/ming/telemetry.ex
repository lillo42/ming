defmodule Ming.Telemetry do
  @moduledoc """
  Provides telemetry helpers for the Ming framework.

  This module wraps `:telemetry` to emit start, stop, and exception events
  with consistent measurements and metadata across the framework.
  """

  @doc """
  Emits a telemetry start event and returns the monotonic start time.

  ## Parameters
  - `event_prefix` - List of atoms forming the event prefix (e.g. `[:ming, :handler, :execute]`)
  - `metadata` - Map of metadata attached to the event
  - `additional_measurements` - Optional extra measurements to include

  ## Returns
  - Monotonic start time as integer
  """
  def start(event_prefix, metadata \\ %{}, additional_measurements \\ %{}) do
    start_time = System.monotonic_time()
    measurements = Map.put(additional_measurements, :system_time, System.system_time())

    :telemetry.execute(event_prefix ++ [:start], measurements, metadata)

    start_time
  end

  @doc """
  Emits a telemetry stop event with duration calculated from the start time.

  ## Parameters
  - `event_prefix` - List of atoms forming the event prefix
  - `start_time` - Monotonic start time returned by `start/3`
  - `metadata` - Map of metadata attached to the event
  - `additional_measurements` - Optional extra measurements to include
  """
  def stop(event_prefix, start_time, metadata \\ %{}, additional_measurements \\ %{}) do
    measurements = include_duration(start_time, additional_measurements)

    :telemetry.execute(event_prefix ++ [:stop], measurements, metadata)
  end

  @doc """
  Emits a telemetry exception event with duration and error details.

  ## Parameters
  - `event_prefix` - List of atoms forming the event prefix
  - `start_time` - Monotonic start time returned by `start/3`
  - `kind` - Atom describing the exception kind (`:error`, `:exit`, or `:throw`)
  - `reason` - The exception reason
  - `stacktrace` - The stacktrace associated with the exception
  - `metadata` - Map of metadata attached to the event
  - `additional_measurements` - Optional extra measurements to include
  """
  def exception(
        event_prefix,
        start_time,
        kind,
        reason,
        stacktrace,
        metadata \\ %{},
        additional_measurements \\ %{}
      ) do
    measurements = include_duration(start_time, additional_measurements)
    metadata = Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: stacktrace})

    :telemetry.execute(event_prefix ++ [:exception], measurements, metadata)
  end

  defp include_duration(start_time, measurements) do
    end_time = System.monotonic_time()

    Map.put(measurements, :duration, end_time - start_time)
  end
end
