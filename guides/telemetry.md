# Telemetry

Ming emits [`:telemetry`](https://hexdocs.pm/telemetry) span events around the messaging hot paths, so you can build metrics and tracing on top without Ming depending on any reporter or backend.

## Events

Each span emits `:start`, `:stop` and `:exception` events; `:stop` measurements include the `:duration` in native time units.

| Event | Metadata | `:stop` adds |
|---|---|---|
| `[:ming, :produce]` | `:gateway`, `:routing_key`, `:queue`, `:message_id`, `:correlation_id` | `:result` (`:ok` or `{:error, reason}`) |
| `[:ming, :poll]` | `:subscription` | `:batch_size`, or `:error` when the receive failed |
| `[:ming, :process]` | `:subscription`, `:message_id`, `:correlation_id` | `:outcome` (`:ack`, `:nack`, `:defer`, `:error`) |

- `[:ming, :produce]` wraps producing a message through the gateway (all adapters).
- `[:ming, :poll]` wraps each consumer poll of a subscription.
- `[:ming, :process]` wraps dispatching one consumed message to its handler; `:outcome` is what the handler settled to before the `:on_error` policy is applied.

## Consuming events with Telemetry.Metrics

Add `{:telemetry_metrics, "~> 1.0"}` to your application, define metrics from the events, and start a reporter in your supervision tree:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      counter("ming.process.stop.count", tags: [:subscription, :outcome]),
      counter("ming.produce.stop.count", tags: [:gateway, :routing_key]),
      distribution("ming.process.stop.duration",
        unit: {:native, :millisecond},
        tags: [:subscription],
        buckets: [10, 50, 100, 500, 1_000]
      ),
      distribution("ming.produce.stop.duration", unit: {:native, :millisecond}),
      summary("ming.poll.stop.batch_size", tags: [:subscription])
    ]
  end
end

# application.ex
children = [
  {Telemetry.Metrics.ConsoleReporter, metrics: MyApp.Telemetry.metrics(), interval: 30_000}
]
```

The console reporter is convenient in development; in production, swap it for a Prometheus, StatsD or OpenTelemetry reporter of your choice — the events Ming emits stay the same.

## OpenTelemetry

Because Ming emits standard span events, they can be bridged to OpenTelemetry spans from your application with [`:opentelemetry_telemetry`](https://hex.pm/packages/opentelemetry_telemetry), without Ming depending on OpenTelemetry itself. Trace-context propagation through `%Ming.Messaging.Message{}` (W3C `trace_parent`/`trace_state`/`baggage`) is planned as a separate package.
