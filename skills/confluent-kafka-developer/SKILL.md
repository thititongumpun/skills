---
name: confluent-kafka-developer
description: Kafka/Confluent developer skill for design, explanation, diagrams, planning, and review — designs event/topic/schema models, explains Kafka/Kafka Streams/ksqlDB/Flink concepts, draws architecture and data-flow diagrams, plans producer/consumer/streaming implementation work, and reviews Kafka client and Streams topology code. Searches official docs (docs.confluent.io, kafka.apache.org, developer.confluent.io) and community sources (Confluent Community Forum, Stack Overflow, relevant GitHub issues/discussions) before answering. Use when explaining a Kafka concept, designing an event-driven system, drawing a Kafka/Streams diagram, planning Kafka feature work, or reviewing Kafka producer/consumer/Streams/Connect code.
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

1. **Official docs first**: [docs.confluent.io](https://docs.confluent.io/),
   [kafka.apache.org/documentation](https://kafka.apache.org/documentation/),
   [developer.confluent.io](https://developer.confluent.io/) (courses,
   patterns, event-driven design guides), and the relevant client library
   docs (Java, Python, Go, .NET, librdkafka) — use context7 if available
   for exact client API surfaces.
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
for poison messages"). If the user wants this executed rather than just
planned, hand off to the `autopilot` skill.

**Review**: check for the common pitfalls below, and for anything
config-specific, verify current defaults/behavior against docs rather than
assuming.

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
- **Review**: findings framed as root cause + fix location, not just
  symptoms — same discipline as `autopilot`'s review phase.
- **Explanations**: cite the specific doc section retrieved, and flag
  version-dependent behavior.
