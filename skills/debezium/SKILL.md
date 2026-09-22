---
name: debezium
argument-hint: "[question] [db] [version]"
description: Research and recommend Debezium CDC options from the official docs — pick the right connector, snapshot/capture mode, and settings for MySQL, MariaDB, PostgreSQL, SQL Server, Oracle, Db2, MongoDB, Cassandra, Vitess, Spanner, Informix, or CockroachDB on any Debezium series (1.9, 2.x, 3.x); compare Debezium with Confluent-native CDC (Oracle CDC / XStream) and plan version upgrades from release notes. Use when the user asks which Debezium/Confluent CDC option to use, how a Debezium property behaves in a given version, or how to upgrade a Debezium connector. Official Debezium and Confluent docs only.
---

# Debezium research

The deliverable is a ranked recommendation with the doc URL and version behind
each claim, not an answer from memory. Deploying or changing a house connector
is `mfec-kafka-connect`; Connect questions that are not Debezium-specific are
`confluent-kafka-developer`.

## Step 0 — pin the target

Before any fetch, fix four things: database and its version, Debezium series
(default `stable`), runtime (OSS Kafka Connect, Debezium Server, Confluent
Platform plugin, Confluent Cloud managed), and what the user is deciding.
Missing database or runtime: ask one short question. Missing version: use
`stable`, and say which number `stable` resolved to.

## Source map

- Connector page: `https://debezium.io/documentation/reference/<ver>/connectors/<db>.html`.
  `<ver>` is `stable`, `nightly`, `3.7`, `3.6`, `3.5`, `3.4`, `3.3`, `3.2`, `3.1`,
  `3.0`, `2.7`, or `1.9`. `<db>` is `mysql`, `mariadb`, `postgresql`, `sqlserver`,
  `oracle`, `db2`, `mongodb`, `cassandra`, `vitess`, `spanner`, `informix`, or
  `cockroachdb`. `.../connectors/index.html` marks which are incubating.
- Series, EOL, and tested DB/Kafka/Java versions: `https://debezium.io/releases/`;
  breaking changes per series: `https://debezium.io/releases/<series>/`.
- Install and Debezium Server: `.../reference/<ver>/install.html`, `.../reference/<ver>/operations/debezium-server.html`.
- Confluent Platform plugin: `https://docs.confluent.io/kafka-connectors/debezium-<db>-source/current/overview.html`
  (`postgres`, `sqlserver` verified). Find every other slug from
  `https://docs.confluent.io/platform/current/connect/kafka_connectors.html`;
  a guessed slug redirects to the docs home page with HTTP 200, so it looks
  like a fetch that worked and cites nothing.
- Confluent Cloud managed: start at `https://docs.confluent.io/cloud/current/connectors/index.html`
  and follow the link. Confluent's own Oracle CDC Source and Oracle XStream
  connectors live here and are not Debezium.
- Fetching: `ctx_fetch_and_index` gets 200 from `debezium.io`. Plain WebFetch
  gets 403 there; use the `fetch-403` skill, never a guess. context7 has
  `/websites/debezium_io_reference_3_6`, `/websites/debezium_io_reference_3_5`,
  and `/debezium/debezium` (2.7.1) for property lookups: one concept per
  query, three calls max, and the version in the ID must match the target.
- Allowed sources: `debezium.io`, `docs.confluent.io`, and release notes under
  `github.com/debezium`. No blogs, forums, Stack Overflow, or AI summaries, not
  even to confirm a doc claim. If the docs do not settle it, say so.

## Modes

**Recommend.** Fetch the connector page for the pinned version. List the
decision points that page exposes for that database (capture mechanism such as
LogMiner vs XStream vs OpenLogReplicator, `snapshot.mode`, `plugin.name`,
CDC vs change tracking, incremental snapshots, signalling), rank the options
with one trade-off each, and cite the section for every one.

**Compare Debezium vs Confluent-native.** Only when Confluent ships its own
connector for that database (Oracle CDC Source, Oracle XStream, the managed
"V2 (Debezium)" sources). Compare on supported DB versions, capture mechanism,
licence and cost, managed vs self-managed, and feature gaps named in either
doc. Table first, then one pick.

**Upgrade.** Read `https://debezium.io/releases/<series>/` for every series
between current and target, oldest first. Pull breaking changes and property
renames into one list. The 1.x → 3.x renames already seen in production are
in `mfec-kafka-connect`; confirm them against the target series rather than
repeating them.

## Report

Report in this shape, nothing else before it:

```
Target: <db> <db version> · Debezium <series → resolved number> · <runtime>
Recommendation: <one line>
Options (ranked):
1. <option> — <trade-off> — <doc URL#section>
...
Sources: <URL + version> per claim
Unverified: <anything marked "suggested, not verified">
```

Name the version on every version-specific claim. Cap options at five.

## Traps

- **`stable` moves.** Quote the number it resolved to; a URL with `stable` in
  it is not a citation next month.
- **Confluent plugin version ≠ Debezium version.** Read the bundled Debezium
  version from the Confluent page before applying a debezium.io claim.
- **Debezium 2.0 renamed and re-versioned.** `database.server.name` became
  `topic.prefix`, and schema names were centralised; Confluent's PostgreSQL
  page says Schema Registry compatibility may need `NONE` to cross 1.x → 2.x.
- **Incubating connectors** (Vitess, Informix, CockroachDB) may break
  compatibility between minors; say so in the recommendation.
- **Confluent "Oracle CDC Source" is not Debezium.** Do not cite a Debezium
  Oracle property for it, or the reverse.
