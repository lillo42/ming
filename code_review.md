# Code Review: Messaging Gateway Branch

## Summary

This branch adds messaging gateway support to Ming, specifically an AMQP adapter with CloudEvents integration. The feature is well-structured but has several bugs ranging from critical runtime errors to resource leaks and type mismatches.

---

## Already Fixed

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `router.ex` | Duplicate `publish_clauses`, `__register_routing_keys__`, `send/3`, `publish/3`, `do_dispatcher/4`, `resolve_routing_key/2` in `__before_compile__` | Removed duplicate code |
| 2 | `message/handler.ex` | `producer.send/3` called but `Ming.Message.Producer` callback is `publish/2` | Changed to `producer.publish/3` |
| 4 | `gateway/amqp/connection.ex` | `init/1` returned `{:error, reason}` instead of `{:stop, reason}` | Changed to `{:stop, reason}` |
| 6 | `message/trace_state.ex` | `from_string/1` filtered out valid key-value pairs (`!= 2` → `== 2`) | Fixed filter logic |
| 7 | `gateway/amqp/consumer.ex` | `Map.fetch!(metadata, :message_id)` would crash if missing | Changed to `Map.get` with `UUIDv7.generate()` fallback |
| 8 | `gateway/amqp/producer.ex` | List clause called `send/2` instead of `publish/2` | Fixed recursive call |
| 9 | `gateway/amqp/publisher.ex` | `DateTime.diff/2` without `:millisecond` unit | Added `:millisecond` unit |
| 10 | `message.ex` | `timestamp: DateTime.utc_now()` evaluated at compile time | Changed to `timestamp: nil` + added `new/1` helper |
| 11 | `gateway/amqp.ex` | Leftover commented-out `@type` blocks and cryptic comments | Removed dead code |
| 12 | `gateway/amqp.ex` | Unused `command_process` binding in `init/1` | Inlined into `subscriptions/4` call |
| 13 | `ming.ex` | `@type provision(t)` was identical to non-parameterized `provision()` | Fixed to only parameterized form |
| 14 | All new modules | Missing `@moduledoc` | Added module documentation everywhere |
| 16 | `message/middleware/request_to_message.ex` | Typo `:invalid_message_mapper_resposne` | Fixed to `:invalid_message_mapper_response` |
| 17 | `gateway/supervisor.ex` | `:ok = adapter.provision_infrastructure(...)` crashes with unhelpful error | Changed to `case` with descriptive `raise` |
| 20 | `router.ex` | Dead code `resolve_routing_key/2` defined but never called | Removed |
| 32 | `gateway/amqp.ex` | `Keyword.get(args, :subscription, [])` should be `:subscriptions` | Fixed to `:subscriptions` |
| 10 (subagent) | `gateway/amqp/consumer.ex` | `parse_header_value` for `:timestamp` returned `datetime` directly instead of `{key, datetime}` | Fixed return shape |
| 11 (subagent) | `gateway/amqp/consumer.ex` | `parse_header_value` for `:array` with empty list returned `{key, %{}}` instead of `{key, []}` | Fixed to `[]` |
| 14 (subagent) | `gateway/amqp/publisher.ex` | `init_worker` hard-matched `{:ok, channel} = Channel.open(conn)` | Added `case` with `{:remove, ...}` on error |
| 16 (subagent) | `gateway/amqp/message_process.ex` | Missing `handle_checkin/4` — workers never returned to pool | Added `handle_checkin` callbacks |
| 17 (subagent) | `gateway/amqp/publisher.ex` | Missing `handle_checkin/4` — workers never returned to pool | Added `handle_checkin` callbacks |

---

## Remaining Critical Bugs

### 1. `Message.Handler` calls `producer.publish/3` but callback is `publish/2`
**File:** `lib/ming/message/handler.ex` (line 26)  
**Severity:** Critical

```elixir
producer.publish(request, publication, Map.get(assigns, :ming_message_opts, []))
```

The `Ming.Message.Producer` behaviour defines `publish(message_or_messages, opts)` with **2 arguments**. This call passes 3 arguments. The `opts` should be a keyword list that includes `:publication` and `:extra_opts` internally.

**Fix:** Merge `publication` and `ming_message_opts` into a single `opts` keyword list.

---

### 2. `Producer` passes `%DateTime{}` as `:timestamp` to AMQP
**File:** `lib/ming/gateway/amqp/producer.ex` (line 40)  
**Severity:** Critical

```elixir
|> put_if_not_nil(:timestamp, message.timestamp)
```

`Basic.publish` expects `:timestamp` to be a POSIX integer (seconds since epoch), not a `%DateTime{}` struct. This will crash or be rejected by AMQP.

**Fix:** Convert `message.timestamp` to Unix timestamp integer before passing.

---

### 3. Connection leak on channel open failure
**File:** `lib/ming/gateway/amqp.ex` (lines 165-166, 279)  
**Severity:** High

`create_channel` returns `{:error, reason, conn, nil}` when channel open fails. `close_channel({:error, reason, conn, nil})` returns `{:error, reason, conn}` without closing the connection. Then `close_conn` doesn't match this tuple shape properly.

**Fix:** Add `close_conn` clause for `{:error, reason, conn}` and ensure connection is closed when channel open fails.

---

### 4. Missing `ensure_exchange_exists` clause for `{:error, reason, conn, nil}`
**File:** `lib/ming/gateway/amqp.ex` (lines 174-178)  
**Severity:** High

`create_channel` at line 166 can return `{:error, reason, conn, nil}`. None of the `ensure_exchange_exists` clauses match this tuple. It will fall through to `ensure_exchange_exists(val, exchange)` and crash.

**Fix:** Add clause: `defp ensure_exchange_exists({:error, reason, conn, nil}, _exchange), do: {:error, reason, conn, nil}`.

---

### 5. Pool name is `routing_key` which can be a string
**File:** `lib/ming/gateway/amqp.ex` (line 94)  
**Severity:** High

```elixir
name: Keyword.fetch!(publication, :routing_key)
```

NimblePool names must be valid process names (atoms or `{:global, ...}`). If `routing_key` is a string, the pool will crash on startup.

**Fix:** Use a dedicated `:name` atom from config, or derive an atom from the routing key.

---

### 6. `Consumer.init/1` hard match on `Channel.open`
**File:** `lib/ming/gateway/amqp/consumer.ex` (line 36)  
**Severity:** Medium

```elixir
{:ok, channel} = Channel.open(conn)
```

If channel open fails, the GenServer crashes without returning `{:stop, reason}`.

**Fix:** Use `case Channel.open(conn) do ... end` and return `{:stop, reason}` on failure.

---

### 7. `delivery_tag` can be `nil`
**File:** `lib/ming/gateway/amqp/consumer.ex` (line 101)  
**Severity:** High

```elixir
Map.get(metadata, :delivery_tag)
```

If `:delivery_tag` is missing from metadata, `nil` is passed to `Basic.ack/2` or `Basic.reject/2`, which will crash.

**Fix:** Use `Map.fetch!(metadata, :delivery_tag)` or handle `nil` explicitly.

---

### 8. `parse_timestamp` crashes on string input
**File:** `lib/ming/gateway/amqp/consumer.ex` (lines 178-186)  
**Severity:** Medium

```elixir
DateTime.from_unix(val, :second)
```

If `val` is a string (ISO 8601 from CloudEvents header), this crashes.

**Fix:** Check `is_integer(val)` before calling `from_unix`, or try `DateTime.from_iso8601/1` for strings.

---

### 9. `source` default is `URI` struct, not string
**File:** `lib/ming/gateway/amqp/consumer.ex` (line 133)  
**Severity:** Medium

```elixir
source: Map.get(headers, "cloudEvents:source", URI.parse("https://hex.pm/packages/ming"))
```

Default is `%URI{}` struct, but if header is present it's a string. Type inconsistency in the struct.

**Fix:** Convert default to string: `URI.to_string(URI.parse(...))`.

---

### 10. `Publisher.handle_ping` returns invalid `{:remove, :idle_timeout}`
**File:** `lib/ming/gateway/amqp/publisher.ex` (line 87)  
**Severity:** High

```elixir
{:remove, :idle_timeout}
```

NimblePool `handle_ping` should return `{:remove, worker_state}` or `{:remove, reason}`. The atom `:idle_timeout` is not a valid worker state.

**Fix:** Return `{:remove, worker_state}` or `{:remove, %{}}`.

---

### 11. `MessageProcess.checkout!` can raise
**File:** `lib/ming/gateway/amqp/message_process.ex` (line 20)  
**Severity:** Medium

```elixir
NimblePool.checkout!(name, :process, fn ... end)
```

If pool is empty, `checkout!` raises. Should use `checkout` with timeout or handle the error.

**Fix:** Use `NimblePool.checkout/4` with timeout and handle `:error`.

---

### 12. Infinite requeue on handler error
**File:** `lib/ming/gateway/amqp/message_process.ex` (line 33)  
**Severity:** High

```elixir
{:error, _reason} -> Basic.reject(channel, delivery_tag, requeue: true)
```

Failed messages are requeued forever. No max retry count or dead-letter mechanism.

**Fix:** Add retry counting with dead-letter after max retries, or use `requeue: false` for permanent errors.

---

### 13. Infinite recursion on non-keyword list in baggage
**File:** `lib/ming/message/baggage.ex` (line 90)  
**Severity:** High

```elixir
do_string(value)  # when value is a non-keyword list
```

Calls itself with the same list, causing infinite recursion.

**Fix:** Handle non-keyword lists with `Enum.map_join/3` or similar.

---

### 14. `URI.encode` is deprecated
**File:** `lib/ming/message/baggage.ex` (line 94)  
**Severity:** Low

```elixir
URI.encode(Kernel.to_string(value))
```

`URI.encode/1` is deprecated in newer Elixir versions.

**Fix:** Use `URI.encode_www_form/1` or `URI.encode/2` with a predicate.

---

### 15. `get_connection!` returns stale struct after restart
**File:** `lib/ming/gateway/amqp/connection.ex` (lines 24-26)  
**Severity:** Medium

```elixir
def get_connection!(name) do
  GenServer.call(name, :get_connection)
end
```

If the connection process dies and restarts, callers get the old cached struct and will fail when opening channels.

**Fix:** Verify connection is alive before returning, or use a registry.

---

### 16. No backoff on connection failure
**File:** `lib/ming/gateway/amqp/connection.ex` (lines 41-48)  
**Severity:** Medium

If `AMQP.Connection.open` fails, the GenServer crashes. The Supervisor restarts it immediately. No exponential backoff — could cause a tight restart loop.

**Fix:** Add retry with backoff in `init/1`, or use a separate connection manager.

---

### 17. `ensure_exchange_exists` passes error through for string exchange
**File:** `lib/ming/gateway/amqp.ex` (line 180)  
**Severity:** Medium

```elixir
defp ensure_exchange_exists(val, exchange) when is_binary(exchange), do: val
```

If `val` is an error tuple and `exchange` is a string, it passes through without closing resources.

**Fix:** Check `val` is success before passing through.

---

### 18. `close_conn` missing clause for `{:error, reason, conn, nil}`
**File:** `lib/ming/gateway/amqp.ex` (lines 296-306)  
**Severity:** Medium

`close_channel` can return `{:error, reason, conn}` (from line 279) or `{:error, reason, conn, nil}` (not handled). Then `close_conn` doesn't match `{:error, reason, conn, nil}`.

**Fix:** Add clause: `defp close_conn({:error, reason, conn, nil}), do: close_conn({:error, reason, conn})`.

---

### 19. Missing catch-all `handle_info` in Consumer
**File:** `lib/ming/gateway/amqp/consumer.ex`  
**Severity:** Medium

No catch-all `handle_info` clause. Unexpected AMQP messages will crash the GenServer.

**Fix:** Add `def handle_info(_msg, state), do: {:noreply, state}`.

---

### 20. `UUIDv7.generate()` without alias
**File:** `lib/ming/gateway/amqp/consumer.ex` (lines 122, 125)  
**Severity:** Low

`UUIDv7.generate()` is called but there's no `alias UUIDv7`. Works if in global scope, but fragile.

**Fix:** Add `alias UUIDv7` or use full module name.

---

### 21. `close_channel` doesn't close connection when channel is nil
**File:** `lib/ming/gateway/amqp.ex` (line 279)  
**Severity:** Medium

```elixir
defp close_channel({:error, reason, conn, nil}), do: {:error, reason, conn}
```

Channel is `nil` (wasn't opened), but connection `conn` is not closed. Connection is leaked.

**Fix:** Close connection: `AMQP.Connection.close(conn); {:error, reason}`.

---

### 22. `close_conn({:ok, conn})` returns `:ok` not `{:ok, conn}`
**File:** `lib/ming/gateway/amqp.ex` (lines 304-306)  
**Severity:** Medium

```elixir
defp close_conn({:ok, conn}) do
  AMQP.Connection.close(conn)
end
```

Returns `:ok` from `AMQP.Connection.close/1`. The pipeline expects `{:ok, conn}` or error tuple. Inconsistent return type.

**Fix:** Return `:ok` explicitly, or `{:ok, nil}` for consistency.

---

### 23. `ensure_queue_is_bind` `:validate` doesn't validate
**File:** `lib/ming/gateway/amqp.ex` (lines 267-268)  
**Severity:** Low

```elixir
defp ensure_queue_is_bind(:validate, _channel, _queue, _exchange), do: :ok
defp ensure_queue_is_bind({:validate, _opts}, _channel, _queue, _exchange), do: :ok
```

`:validate` provision strategy for queues does not validate the binding actually exists. Might be a bug if user expects validation.

**Fix:** Implement binding validation or document that `:validate` only validates queue/existence, not bindings.

---

### 24. `:ok = Channel.close(channel)` crashes if close fails
**File:** `lib/ming/gateway/amqp/consumer.ex` (line 56)  
**Severity:** Low

```elixir
{:error, reason} ->
  :ok = Channel.close(channel)
  {:stop, reason}
```

If `Channel.close` returns `{:error, _}`, this crashes instead of stopping cleanly.

**Fix:** Use `Channel.close(channel)` without match, or handle both `:ok` and `{:error, _}`.

---

### 25. `||` treats empty string as falsy for `id`
**File:** `lib/ming/gateway/amqp/consumer.ex` (line 122)  
**Severity:** Low

```elixir
id: Map.get(headers, "cloudEvents:id") || Map.get(metadata, :message_id, UUIDv7.generate())
```

If `headers["cloudEvents:id"]` is `""` (empty string), `||` treats it as falsy and falls back. Should use explicit `nil` check.

**Fix:** Use `Map.get(headers, "cloudEvents:id") || ...` is fine for empty strings, but if empty string is valid ID, use `is_nil` check.

---

### 26. `new/1` assumes map, crashes on keyword list
**File:** `lib/ming/message.ex` (lines 34-36)  
**Severity:** Medium

```elixir
def new(attrs \\ %{}) do
  struct!(__MODULE__, Map.put_new(attrs, :timestamp, DateTime.utc_now()))
end
```

If `attrs` is a keyword list, `Map.put_new` will crash.

**Fix:** Accept both map and keyword list: `attrs = Map.new(attrs)`.

---

### 27. `ensure_queue_is_bind` typo in function name
**File:** `lib/ming/gateway/amqp.ex` (lines 266-276)  
**Severity:** Low

Function is named `ensure_queue_is_bind` but should be `ensure_queue_is_bound` (grammar).

**Fix:** Rename to `ensure_queue_is_bound`.

---

## Design / Architecture Concerns

### 28. No tests for new code
The diff shows no new tests for the messaging gateway, message parsing, CloudEvents handling, or AMQP integration. The only test change is a blank line in `dispatcher_test.exs`.

**Recommendation:** Add tests for:
- `Ming.Message` struct creation and `new/1`
- `Ming.Message.Baggage` parsing/serialization
- `Ming.Message.TraceState` parsing/serialization
- `Ming.Gateway.AMQP` provisioning logic
- `Ming.Gateway.AMQP.Consumer` message parsing
- `Ming.Gateway.AMQP.Producer` publish options building
- `Ming.Gateway.AMQP.Publisher` pool behavior
- `Ming.Message.Middleware.MessageToRequest` and `RequestToMessage`

### 29. `Ming.Gateway.Supervisor` provisioning blocks init
`provision_infrastructure/1` is called synchronously in `init/1`. If provisioning fails, the entire supervisor crashes. This is by design but may be too strict for production.

**Recommendation:** Consider using `handle_continue` or a separate provisioning task.

### 30. AMQP modules conditional compilation
All AMQP modules use `if Code.ensure_loaded?(AMQP)`. If a user tries to start `Ming.Gateway.AMQP` without the AMQP dependency, the module won't exist and the error will be confusing.

**Recommendation:** Add a helpful error message in `Ming.Gateway.Supervisor` when the adapter module is not loaded.

---

## Recommendations

| Priority | Action |
|----------|--------|
| **Critical** | Fix `Message.Handler` to pass 2 args to `publish/2` |
| **Critical** | Fix `Producer` to pass integer timestamp to AMQP |
| **High** | Fix connection leak on channel open failure |
| **High** | Fix missing `ensure_exchange_exists` clause for `{:error, reason, conn, nil}` |
| **High** | Fix pool name to be an atom, not routing_key string |
| **High** | Fix infinite requeue on handler error |
| **High** | Fix infinite recursion in `Baggage.do_string/1` |
| **Medium** | Fix `Consumer.init/1` to handle `Channel.open` failure gracefully |
| **Medium** | Fix `delivery_tag` nil handling |
| **Medium** | Fix `parse_timestamp` to handle string input |
| **Medium** | Fix `Publisher.handle_ping` return value |
| **Medium** | Add backoff to connection retry |
| **Medium** | Add catch-all `handle_info` to Consumer |
| **Medium** | Fix `new/1` to accept keyword lists |
| **Low** | Fix `URI.encode` deprecation |
| **Low** | Fix `ensure_queue_is_bind` typo |
| **Low** | Add `alias UUIDv7` in Consumer |
| **Low** | Fix `close_conn` return type consistency |

---

*Review generated for branch `add-support-messaging-gateway` vs `main`*
