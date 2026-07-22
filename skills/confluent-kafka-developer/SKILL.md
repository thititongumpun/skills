---
name: confluent-kafka-developer
description: Kafka/Confluent developer skill for design, implementation, and review of application work — producers, consumers, Kafka Streams, Kafka Connect, ksqlDB, and Flink. Designs event/topic/schema models, writes and reviews client code and connector/ksqlDB/Flink SQL config, explains Kafka concepts, and draws architecture and data-flow diagrams. Searches official docs (docs.confluent.io, kafka.apache.org, developer.confluent.io) and community sources (Confluent Community Forum, Stack Overflow, relevant GitHub issues/discussions) before answering. Use when explaining a Kafka concept, designing an event-driven system, drawing a Kafka/Streams diagram, planning or writing producer/consumer/Streams/Connect/ksqlDB/Flink code and config, or reviewing any of it.
---

# Confluent / Kafka Developer

For cluster provisioning, RBAC/networking, or ops — use
`confluent-kafka-admin` instead. This skill is for designing, explaining,
diagramming, planning, and reviewing Kafka *application* work.

## Research workflow

Kafka/Confluent APIs, client configs, and best practices change across
versions (KRaft, tiered storage, exactly-once semantics, new client
configs) — don't answer from pretrained memory alone for anything
version-specific.

1. **Official docs first**: start from
   [docs.confluent.io/llms.txt](https://docs.confluent.io/llms.txt) —
   Confluent's LLM-oriented doc index (~150 links organized by product/topic:
   Cloud, Platform, Flink, connectors, clients, security, CLI, etc.) — to
   find the right page fast, then fetch that specific page for exact
   details. Use
   [llms-full.txt](https://docs.confluent.io/llms-full.txt) for grounding
   on terminology/glossary questions, not as a substitute for the actual
   page. Also check [kafka.apache.org/documentation](https://kafka.apache.org/documentation/)
   for OSS-specific behavior, [developer.confluent.io](https://developer.confluent.io/)
   for patterns/courses/event-driven design guides,
   [Apache Flink docs](https://nightlies.apache.org/flink/flink-docs-stable/)
   for engine-level Flink behavior (SQL/Table API/DataStream reference,
   connectors, state, watermarks — no `llms.txt`, fetch the specific page),
   and the relevant client library docs (Java, Python, Go, .NET,
   librdkafka) — use context7 if available for exact client API surfaces.
2. **Community sources when docs don't settle it**: a specific error
   message, an edge case, or "does X actually behave like Y in practice" —
   search the [Confluent Community Forum](https://forum.confluent.io/),
   Stack Overflow (`apache-kafka`, `confluent-platform` tags), and relevant
   GitHub issues/discussions (`apache/kafka`, `confluentinc/*`).
3. **Cite what you find and flag conflicts**: if community info contradicts
   the docs or looks version-specific/stale, say so rather than silently
   picking one.

## Task modes

**Explain/understand**: ground the explanation in retrieved docs; call out
version-specific behavior explicitly (e.g., pre- vs. post-KRaft, exactly-once
semantics changes across broker/client versions).

**Design**: cover topic naming and partitioning strategy, key design,
schema format (Avro/Protobuf/JSON Schema) and Schema Registry compatibility
mode, delivery semantics (at-least-once vs. exactly-once), consumer group
strategy, event-vs-command modeling, ordering guarantees, and
retention/compaction choice. Weigh 2-3 approaches with trade-offs and commit
to a recommendation with a one-line rationale, then confirm scope with the
user before finalizing — don't just present a menu.

**Diagram**: default to Mermaid (renders natively in Claude Code/artifacts).
Use flowcharts for producer→topic→consumer data flow, sequence diagrams for
request/response or Streams processing order, and component diagrams for
multi-service/cluster architecture. Show partition/consumer-group
relationships explicitly when they're the point of the diagram.

**Plan tasks**: break Kafka feature work into concrete implementation
tasks (e.g., "define Avro schema + compatibility mode", "configure
idempotent producer", "write Streams topology + tests", "add DLQ handling
for poison messages"). For a large multi-task build the user wants driven
end to end, hand off to the `autopilot` skill.

**Implement**: write the code or config, don't stop at a plan. Retrieval
still applies — verify config keys, SQL syntax, and API surfaces against
docs before writing, because a plausible-but-wrong property name fails at
runtime, not at compile time, and often only under load. Match the
project's existing client library, serialization format, and config style
rather than introducing a second way of doing it. What "done" means per
surface:

- **Producer**: `acks`/`enable.idempotence`/retry config matching the
  delivery guarantee you claim, serializer + Schema Registry config, a
  deliberate key strategy (partitioning consequences stated), and a send
  error path — not fire-and-forget with an ignored future/callback.
- **Consumer**: group id, offset-commit strategy matched to the processing
  guarantee (commit-after-process for at-least-once), poll-loop timing
  within `max.poll.interval.ms`, poison-message/DLQ path, and defined
  rebalance behavior.
- **Connect**: connector class + converters matching what's actually on the
  topic, SMT chain in applied order, `errors.tolerance` + DLQ topic, and
  exactly-once claimed only if that specific connector supports it.
- **ksqlDB**: statements with explicit key/value formats and partition
  counts, co-partitioning verified for joins, and a materialized table
  where pull queries are needed.
- **Flink**: watermark + allowed lateness stated, changelog mode matching
  the sink topic, bounded state (TTL or window), and checkpointing that
  actually supports the claimed guarantee.

Leave one runnable check behind — a test against an embedded broker or
Testcontainers, Connect's `/connector-plugins/{class}/config/validate`
endpoint, `EXPLAIN` on a Flink or ksqlDB statement, or at minimum a
produce/consume round trip. Config that has never been executed is a
hypothesis.

**Review**: check for the common pitfalls below, and for anything
config-specific, verify current defaults/behavior against docs rather than
assuming.

## Confluent Cloud (developer-facing)

For provisioning/RBAC/networking use `confluent-kafka-admin` — this is the
"how does my application code talk to Confluent Cloud" side.

- **Client connection config**: `bootstrap.servers` (cloud endpoint),
  `security.protocol=SASL_SSL`, `sasl.mechanism=PLAIN`, and API
  key/secret as `sasl.jaas.config` (or the client library's equivalent
  cloud-config helper, e.g. `confluent-kafka-python`'s cloud config
  block). Never hardcode API keys/secrets in source — use env vars or a
  secrets manager, same as any credential.
- **Schema Registry**: Confluent Cloud Schema Registry has its own
  endpoint and API key/secret pair, separate from the Kafka cluster's —
  a common source of "works for produce, fails for schema registration"
  bugs when the two get conflated.
- **Local dev/testing**: `confluent kafka topic produce/consume` for quick
  manual testing against a Cloud topic, `confluent flink shell` for
  interactive Flink SQL against Cloud compute pools, and `confluent local`
  for spinning up an ephemeral local broker when you want to test without
  touching Cloud at all.
- **Fully-managed services**: prefer a Confluent Cloud fully-managed
  connector, Cloud ksqlDB app, or Cloud Flink compute pool over
  self-hosting the equivalent, unless there's a specific reason
  (unsupported connector, custom SMT, cost) — check current
  [Cloud connector](https://docs.confluent.io/cloud/current/connectors/index.html)
  and [Cloud Flink](https://docs.confluent.io/cloud/current/flink/index.html)
  docs for what's supported before assuming self-managed is required.
- **Cluster Linking**: if the design spans multiple Cloud clusters/regions
  or a hybrid Cloud+self-managed setup, that's a `confluent-kafka-admin`
  concern for the linking setup itself, but affects application design
  (topic availability, read-your-writes across linked clusters) — flag it
  rather than silently assuming a single cluster.

## Flink, ksqlDB, and Kafka Connect

Application-level design/review for these three, same research-first rule
as everything else — SQL syntax, connector configs, and operators change
across versions.

**ksqlDB**: streams vs. tables semantics, push vs. pull query choice,
materialized views for pull queries, `WITH` clause config (key format,
value format, partitions), joins requiring co-partitioning, windowed
aggregations (tumbling/hopping/session) and their retention, and how a
persistent query maps to an underlying Kafka Streams app (so Streams
pitfalls below still apply). Retrieve current
[ksqlDB syntax reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
before writing non-trivial statements.

**Flink (Confluent Cloud for Apache Flink / self-managed Flink)**:
watermark strategy and allowed lateness (drives correctness of windowed/
time-based logic), event-time vs. processing-time choice,
checkpointing/state backend for exactly-once, and Table API vs. DataStream
API vs. Flink SQL fit for the task.

*Which docs:* Confluent Cloud Flink for the managed surface — catalogs,
compute pools, statements, what's supported — via
[Cloud Flink docs](https://docs.confluent.io/cloud/current/flink/index.html);
[Apache Flink docs](https://nightlies.apache.org/flink/flink-docs-stable/)
for engine semantics (watermarks, state, joins, functions) and anything
self-managed. Engine behavior is shared, the managed surface is not — don't
cite a Cloud-only feature for a self-managed deployment, or an Apache
connector/UDF as available on Cloud, without checking. `flink-docs-stable`
tracks whatever the current release is; name the version when a behavior is
version-specific.

*Confluent Cloud specifics worth designing around:* the catalog model maps
environment → catalog and Kafka cluster → database, so every topic is
already queryable as a table with its Schema Registry schema attached — no
DDL to read an existing topic. Statements run on a compute pool (the
billing/scaling unit) and long-running ones keep running after you
disconnect. Verify current support (Table API, UDFs, connectors to
non-Kafka systems, private networking) against the docs rather than
assuming parity with open-source Flink.

**Kafka Connect**: source vs. sink connector fit, converter choice (Avro/
Protobuf/JSON Schema vs. plain JSON — must match what producers/consumers
on the topic expect), single message transforms (SMTs) and their chaining
order, `errors.tolerance`/dead-letter-queue config for bad records, and
exactly-once support (per-connector, not universal — verify for the
specific connector). For Confluent Cloud, check whether a fully-managed
connector exists before designing a custom one.

### Pitfalls specific to these

- ksqlDB: pull query issued against a stream (not a materialized table) —
  will fail or behave unexpectedly.
- ksqlDB/Streams joins on mismatched keys/partition counts (not
  co-partitioned) — join silently returns no results instead of erroring.
- Flink: watermark/lateness misconfigured — late events silently dropped
  instead of handled, or windows never fire.
- Flink: checkpointing disabled or interval too large for the exactly-once
  guarantee the pipeline claims to provide.
- Flink SQL: changelog mode mismatched with the sink topic — a query
  producing updates/retractions written as append-only (or an upsert sink
  with no primary key declared) silently produces a topic that doesn't say
  what the pipeline thinks it says.
- Flink: unbounded state from a join or aggregation with no TTL/window —
  state grows forever, and on Cloud that's a bill as well as a failure.
- Connect: SMT chain ordering wrong (e.g., a field-rename after a filter
  that already needed the original name) — SMTs apply in the order listed.
- Connect: no `errors.tolerance=all` + DLQ configured — one bad record can
  halt the whole connector task.
- Connect: assuming a connector supports exactly-once without checking —
  it's connector-specific (verify against that connector's docs).

## Common pitfalls to check for

- Missing `acks=all` + `min.insync.replicas` for durability, or missing
  `enable.idempotence` where exactly-once producer semantics are needed.
- Partition key choices that create hot partitions (skewed load across
  consumers).
- Short `session.timeout.ms`/`max.poll.interval.ms` or missing
  `group.instance.id` (static membership) causing rebalance storms.
- No dead-letter-queue or poison-message handling in consumers/Streams
  processors — one bad record blocking the whole partition.
- Schema Registry compatibility mode mismatched with the actual evolution
  pattern needed (e.g., `BACKWARD` chosen but producers need to add
  required fields).
- Kafka Streams: unsized/unbounded state stores, missing standby replicas
  for HA, or `exactly_once_v2` not set where required.
- Manual vs. auto offset commit mismatched with the processing guarantee
  the code actually needs (commit-before-process vs. commit-after-process).
- Partition count treated as easily changeable — it's a hard ceiling on
  consumer parallelism and effectively can't be shrunk.

## Output defaults

- **Design**: recommended approach + rationale, topic/schema/partitioning
  specifics, and open decisions for the user.
- **Diagrams**: Mermaid source, scoped to the question asked (don't diagram
  the whole system when only one flow was asked about).
- **Implement**: the code/config, the check that proves it runs, and any
  setting deliberately left at its default called out — silence about a
  durability or ordering config reads as a decision nobody made.
- **Review**: findings framed as root cause + fix location, not just
  symptoms — same discipline as `autopilot`'s review phase.
- **Explanations**: cite the specific doc section retrieved, and flag
  version-dependent behavior.
