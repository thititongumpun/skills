---
name: rabbitmq
argument-hint: "[design|implement|review|ops|verify] <queue, exchange, consumer, or question>"
description: RabbitMQ developer + operator: exchange/queue/binding design, quorum vs classic queues vs streams, publisher confirms, consumer acks/prefetch, DLX/retry and poison-message handling, idempotent consumers, policies, rabbitmqctl/rabbitmqadmin/HTTP API checks, and an end-to-end verify that proves messages flow. Official docs only. Use when designing a RabbitMQ topology, writing or reviewing publisher/consumer code (pika, aio-pika, Java, .NET, Go), debugging stuck/redelivered/lost messages or dropped connections, choosing a queue type, or inspecting a broker.
---

# RabbitMQ (developer + operator)

One skill for both sides: application topology/code and the broker checks that
prove it works. Default stack (match the project if it differs): Python +
`pika` 1.3.x `BlockingConnection`, AMQP 0-9-1 on 5672, broker in Docker /
Docker Compose, vhost `/`, credentials from env vars.

## Research workflow

Queue-type features, defaults, and limits change between release series
(classic mirroring removed in 4.0, quorum delivery limit added in 4.0, quorum
priorities and delayed retry added in 4.3). Don't answer version-sensitive
questions from memory.

1. **Pin the broker version first.** `rabbitmqctl version` /
   `rabbitmq-diagnostics server_version`, the image tag in
   `docker-compose.yml`/Helm values, or `GET /api/overview`. If unknown, say
   which version you assumed. The docs site defaults to the latest series;
   check the version picker and
   [release-information](https://www.rabbitmq.com/release-information) for
   what's still supported.
2. **Official docs first**: [rabbitmq.com/docs](https://www.rabbitmq.com/docs).
   Core pages: [queues](https://www.rabbitmq.com/docs/queues),
   [quorum-queues](https://www.rabbitmq.com/docs/quorum-queues),
   [streams](https://www.rabbitmq.com/docs/streams),
   [confirms](https://www.rabbitmq.com/docs/confirms) (publisher confirms +
   consumer acks + prefetch),
   [consumers](https://www.rabbitmq.com/docs/consumers),
   [dlx](https://www.rabbitmq.com/docs/dlx),
   [priority](https://www.rabbitmq.com/docs/priority),
   [policies](https://www.rabbitmq.com/docs/policies),
   [heartbeats](https://www.rabbitmq.com/docs/heartbeats),
   [reliability](https://www.rabbitmq.com/docs/reliability),
   [management-cli](https://www.rabbitmq.com/docs/management-cli)
   (rabbitmqadmin v2), [cli](https://www.rabbitmq.com/docs/cli),
   [monitoring](https://www.rabbitmq.com/docs/monitoring).
3. **context7 for client API surfaces**: `resolve-library-id` then
   `query-docs`, one concept per query, three calls max. Known-good IDs:
   `/pika/pika`, `/mosquito/aio-pika`. Match the client version pinned in
   `requirements.txt`/`pom.xml`/`go.mod`.
4. **Official sources only**: `rabbitmq.com`, the official client library
   docs/source (`github.com/rabbitmq/*`, `github.com/pika/pika`), and
   context7 entries built from them. No Stack Overflow, blogs, Medium, or AI
   summaries, not even to confirm a doc claim.
5. **When docs don't settle it, say so** and go empirical: reproduce against
   a throwaway `rabbitmq:<version>-management` container and observe.
6. **Cite** the doc section URL (with `#anchor`) and the series it applies to.

## Task modes

**Design**: decide and state, per flow:
- *Exchange type*: default exchange (`""`, routes by queue name) only for a
  single point-to-point work queue; `direct` for named routes, `topic` for
  hierarchical keys (`order.created.eu`), `fanout` for broadcast, `headers`
  rarely. Prefer a named exchange so routing can change without touching
  publishers.
- *Queue type*:
  - **quorum**: default for anything that must survive a node loss; Raft-
    replicated; poison-message handling via `delivery-limit` (default 20 since
    4.0); at-least-once dead-lettering; priorities and delayed retry from 4.3.
  - **classic**: single-node, non-replicated; fine for transient/exclusive/
    reply queues and single-node dev brokers. No mirroring since 4.0.
  - **stream**: append-only replayable log, non-destructive reads, multiple
    consumers at different offsets, large fan-out; not a work queue.
  - Queue type is set by `x-queue-type` at declare time and can't be changed
    by policy or redeclare; migrating = new queue + rebind + drain old.
- *Naming*: `<domain>.<purpose>` plus `.dlq`, `.retry` siblings; names are
  how policies match (regex), so keep them pattern-friendly.
- *Arguments vs policies*: put tunables (`delivery-limit`, DLX, TTL,
  `max-length`, `consumer-timeout`) in **policies**, which can change live.
  Only `x-queue-type` (and classic `x-max-priority`) belong in the declare.
  Redeclaring with different arguments fails with `PRECONDITION_FAILED`
  (inequivalent arg).
- *Priority*: only if consumers really must reorder. Classic: `x-max-priority`
  1-255, single digits recommended (one sub-queue per level). Quorum (4.3+):
  32 levels, unset priority treated as 4. Prefetch limits how much priority
  can actually reorder.
Weigh 2-3 options, recommend one with a one-line rationale, confirm scope.

**Implement**: write the code/config, then verify (below). Match the
project's client and style. What "done" means:
- **Connection**: credentials from env, `heartbeat` set deliberately,
  reconnect loop with backoff, a single connection per process and a channel
  per thread (pika channels are not thread-safe; use
  `connection.add_callback_threadsafe` to ack from another thread).
- **Declare**: idempotent declares on startup for what this service owns
  (exchange, queue, binding, DLX targets), `durable=True`.
- **Publisher**: `channel.confirm_delivery()`, `mandatory=True`,
  `delivery_mode=pika.DeliveryMode.Persistent`, `content_type`, a stable
  `message_id`; handle `pika.exceptions.UnroutableError` / `NackError` (retry
  or surface), never fire-and-forget. Confirm = persisted (classic) or
  accepted by a quorum of replicas (quorum).
- **Consumer**: long-lived `basic_consume` with `auto_ack=False` and
  `basic_qos(prefetch_count=N)`, not a `basic_get` polling loop (docs: highly
  inefficient; prefetch doesn't apply to `basic_get`). Slow jobs: prefetch
  1-few. Ack after side effects are committed. Decide per failure class:
  - transient (dependency down) -> retry with delay (see Retry), not a hot
    `nack(requeue=True)`;
  - permanent (bad payload, business rule) -> `basic_reject(requeue=False)`
    to DLX, or record the failure and ack;
  - unknown exception -> bounded retries, then DLX.
- **Long-running handlers** (AI/HTTP calls, minutes): the AMQP thread must
  keep servicing heartbeats (run work in a worker thread and call
  `connection.process_data_events(time_limit=...)` /
  `add_callback_threadsafe`), and the ack must arrive inside the
  delivery-acknowledgement timeout (`consumer_timeout`, default 30 min;
  per-queue `consumer-timeout` policy). Exceeding it closes the channel with
  `PRECONDITION_FAILED` and requeues everything unacked on it.

**Retry and DLX**:
- DLX fires on: reject/nack with `requeue=false`, per-message/queue TTL
  expiry, length-limit overflow, and quorum `delivery-limit` exceeded.
  Dead-lettered messages keep their routing key unless the queue sets
  `x-dead-letter-routing-key`; they carry an `x-death` header.
- Every work queue gets a DLQ via policy:
  `{"dead-letter-exchange":"<dlx>","dead-letter-routing-key":"<q>.dlq"}`.
- Quorum: for no-loss DLQ set `dead-letter-strategy: at-least-once` with
  `overflow: reject-publish` (more resources; read the caveats).
- Delayed retry options, newest first: quorum delayed retry (4.3+,
  `delayed-retry-type/min/max` policy keys, linear back-off); or a TTL'd
  `.retry` queue whose DLX points back at the work exchange, with retry
  count read from `x-death` and a cap that ends in the DLQ.
- Don't rely on `delivery-limit` alone: per the 4.x quorum docs, only failed
  deliveries (reject, channel/connection closed with unacked messages)
  increment `delivery-count`; check the target version's docs for whether a
  `nack(requeue=True)` counts.

**Idempotency**: delivery is at-least-once (redelivery after connection loss,
consumer timeout, requeue). Derive a deterministic key from business identity
(or `message_id`), check-and-record it in the same store/transaction as the
side effect (unique index / upsert), and ack duplicates without reprocessing.
`redelivered=True` is a hint, not a guarantee. Streams additionally support
publisher-side dedup with a named producer + strictly increasing publishing ID.

**Ops / inspect** (`rabbitmqctl` runs on the node, e.g.
`docker compose exec rabbitmq rabbitmqctl ...`; `rabbitmqadmin` v2 and the
HTTP API work remotely on 15672):
```bash
rabbitmq-diagnostics -q ping && rabbitmq-diagnostics -q status
rabbitmq-diagnostics -q check_port_connectivity
rabbitmqctl list_queues -p / name type durable messages_ready messages_unacknowledged consumers
rabbitmqctl list_exchanges -p / name type durable
rabbitmqctl list_bindings -p / source_name destination_name routing_key
rabbitmqctl list_consumers -p /
rabbitmqctl list_connections name user state channels
rabbitmqctl list_policies -p /
rabbitmqctl set_policy -p / work-dlx '^work\.' \
  '{"dead-letter-exchange":"work.dlx","delivery-limit":5}' --apply-to quorum_queues
rabbitmqadmin show overview
rabbitmqadmin --vhost / list queues
rabbitmqadmin --vhost / queues declare --name work.jobs --type quorum --durable true
rabbitmqadmin --vhost / exchanges bind --source work --destination-type queue \
  --destination work.jobs --routing-key jobs
rabbitmqadmin definitions export ...   # back up topology before changes
```
For `definitions export`, `publish`, and `get` flags, run `rabbitmqadmin <cmd> --help`. Both are for dev/
test only. Purging or deleting queues destroys messages: confirm with the user
first, never in production without an explicit go-ahead.

**Review**: run the pitfalls list against the code and the live
policies/arguments (`list_queues ... arguments policy`, `list_policies`);
each finding = root cause + location + doc link.

## Verify: prove messages flow

Done means a message went publisher -> exchange -> queue -> consumer -> ack,
and the failure path reached the DLQ. Minimum:

1. Topology exists: `list_exchanges`, `list_queues ... type arguments policy`,
   `list_bindings` show what the design says (type, durable, DLX via policy).
2. Consumer is attached: `consumers >= 1` on the queue,
   `list_consumers` shows the prefetch.
3. Happy path: publish one tagged message with confirms + `mandatory`
   (`UnroutableError` = binding/routing key wrong) and observe
   `messages_ready` 0 -> 1 -> 0 with `messages_unacknowledged` returning to 0,
   plus the consumer's side effect (row/doc/log line keyed by the test id).
4. Failure path: publish a deliberately bad message; it lands in `<q>.dlq`
   (`messages_ready` = 1, `x-death` header present via `rabbitmqadmin get`),
   not in an endless redelivery loop.
5. Duplicate: publish the same business key twice; the side effect happens
   once.
6. Clean up test messages from the DLQ only after the user agrees.

Quick throwaway broker for repro:
`docker run -d --name rmq-test -p 5672:5672 -p 15672:15672 rabbitmq:<series>-management`.

## Pitfalls to check for

- `basic_get` polling loop instead of `basic_consume` + prefetch.
- `auto_ack=True`, or ack before the side effect commits -> message loss.
- No `basic_qos` (unbounded prefetch) -> one consumer hoards the queue,
  memory blowup, priority ineffective.
- `nack(requeue=True)` on every error -> hot redelivery loop that never ends
  for a poison message; no DLQ.
- Publisher without confirms or ignoring `UnroutableError`/`NackError`;
  non-persistent messages to a durable queue the user expects to survive
  restart.
- Handler blocks the pika I/O thread longer than the heartbeat timeout ->
  connection reset, ack fails (`ConnectionResetError`/`StreamLostError`),
  message redelivered and possibly processed twice.
- Job runtime > `consumer_timeout` -> channel closed, all unacked requeued.
- Acking on a different channel/connection than the delivery came on, or
  from a non-I/O thread without `add_callback_threadsafe`.
- Queue arguments hard-coded in clients for tunables -> `PRECONDITION_FAILED`
  on change; use policies.
- Classic queue for data that must survive node loss; leftover classic
  mirroring (`ha-*`) policy keys on 4.x (mirroring removed in 4.0; strip with
  `definitions export --transformations strip_cmq_keys_from_policies,drop_empty_policies`).
- Large `x-max-priority` on classic queues (cost per level).
- Exclusive/auto-delete queues used for durable work; queue names generated
  per process left behind.
- Credentials, hostnames, or passwords committed in compose files or scripts;
  `guest` user (localhost-only by default) used remotely.
- No idempotency key while assuming exactly-once.

## Output defaults

- **Design**: topology table (exchange, type, binding key, queue, queue type,
  policy), recommended option + rationale, open decisions.
- **Diagrams**: invoke `archify` (`workflow` for publish -> route -> consume
  -> DLQ). If unavailable, emit a Mermaid fence and say so.
- **Implement**: code + policies + the verify commands and their observed
  output; call out any setting left at default (prefetch, heartbeat,
  delivery-limit, consumer_timeout) and why.
- **Review / ops**: findings as root cause + fix location + doc link, each
  backed by a command output or the code line; destructive commands proposed,
  not run, until the user confirms.
- **Explain**: cite the doc section and the release series it applies to.
