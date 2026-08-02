## Unreleased
- Change the project license from GPL-3.0 to LGPL-3.0-only
- Add a `:retry` registration option (keyword list of `Ming.retry_opts()` or a plain max-retries integer): any `{:error, _}` response — including handler exceptions and timeouts — re-runs the pipeline with backoff until it succeeds or the retries are exhausted; can be overridden per call
- Add `:requeue_count` subscription option to bound requeues: each requeue increments the `x-ming-requeue-count` header and, once the limit is reached, the message is dead-lettered (AMQP) or forwarded to `:dead_letter_queue_routing_key` (Kafka) instead of looping forever
- **Breaking**: rename the `:number_of_performer` subscription option to `:number_of_performers` in the `:brod` and `:kafka_ex` gateways, matching `Ming.subscription_opts()` and the AMQP gateway
- Remove the unused `:requeue_delay` subscription option from `Ming.subscription_opts()`
- Fix README and guide examples that didn't match the code (middleware tuple form, query support, logger metadata keys) and remove stale `config/test.exs` entries referencing removed modules

## v0.2.0
- Split the project into an umbrella with four apps: `ming` (core), `ming_amqp`, `ming_brod` and `ming_kafka_ex` in https://github.com/lillo42/ming/pull/15
- Add Kafka gateway support via `:brod` and `:kafka_ex` in https://github.com/lillo42/ming/pull/14
- Add AMQP gateway support in https://github.com/lillo42/ming/pull/13
- Rewrite the core pipeline: compile-time routers, `Ming.Context` middleware pipeline and command processor with messaging gateways in https://github.com/lillo42/ming/pull/12
- Add nix flake in https://github.com/lillo42/ming/pull/10

## v0.1.2
- Add support to query in https://github.com/lillo42/ming/pull/9
- Split send & publish logic into their own files in https://github.com/lillo42/ming/pull/8

## v0.1.1
fix: command processor in https://github.com/lillo42/ming/pull/7

## v0.1.0
Initial release.
