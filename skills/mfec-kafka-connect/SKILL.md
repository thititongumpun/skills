---
name: mfec-kafka-connect
argument-hint: "[connector config file or connector name]"
description: Change, deploy, and verify a Kafka Connect connector config in an MFEC customer pipeline (Debezium SQL Server source, JDBC sink, SFTP source, the house SMT library) across dev/uat/prd. Use when editing or adding a connector JSON, bumping a connector version, adding a table to a pipeline, migrating a Debezium version, or asked why a connector or its data is wrong. Official Confluent/Debezium docs only for property semantics.
---

# MFEC Kafka Connect pipelines

A customer pipeline is a folder of connector JSONs plus the scripts and SQL
that prove them. The JSON is not the deliverable — a connector that is
`RUNNING` with the right row counts in the sink is. Every change here ends
with that proof, not with a saved file.

`confluent-kafka-developer` owns generic connector semantics (converters,
SMT chains, DLQ, exactly-once); `confluent-kafka-admin` owns the cluster.
This skill owns the house conventions and the change loop around them.

## Step 0 — read the repo's own record first

Every pipeline repo carries a `README.md` that tables each connector: file,
connector name, source DB, `table.include.list`, delete handling, SMT chain.
Read it before touching a config; it is the current state, and it is what
you update last. If a `connector_checklist*.csv` or `.xlsx` exists (the
upgrade projects keep one: connector name, state, class, owner, config path,
current version), that is the inventory — a connector missing from it is
either orphaned or undocumented, and both are findings.

## Naming — file, connector, and topic are three different names

Config files are versioned by name, never overwritten:

```
<env>-<pipeline>-<src|sink>-<dbz|jdbc|sftp>-<db>-<mst|txn>[-hard_del]-version<N>_<yyyymmdd>_<hhmm>.json
uat-eeas-src-dbz-dbHRMI_Center-txn-version1_20260606_0030.json
```

A config change is a **new file with a new version or timestamp**, so the
previous one stays as the rollback. The connector `name` inside the JSON
follows the customer's own scheme (`EEAS_SRC_DEBEZIUM_CDB_<db>_<txn>_*`),
and the topic name is set by the `RegexRouter`/`standardNaming` transform,
not by either of those — check all three when adding a table, because the
sink's `topics` list and the Schema Registry subject follow the topic.

## Change loop

1. **Edit** the config. For a Debezium table add: `table.include.list`, the
   matching `TopicNameMatches` predicate if a `FilterTimestamp` applies, the
   sink's `topics`, and the IVT checksum SQL for that table — four places,
   all in the README's tables.
2. **Validate before deploying**:
   `PUT <CONNECT_URL>/connector-plugins/<connector.class>/config/validate`
   with the config body; zero `errors` is the bar. This catches a renamed
   property or a missing SMT class on the worker without touching the live
   connector.
3. **Diff against live** — `GET /connectors/<name>/config` — and read the
   diff aloud in the report. A prod change with an unexplained line in the
   diff is not ready.
4. **Deploy** with `PUT /connectors/<name>/config` (create-or-update; it
   keeps the name stable so offsets survive). Then `GET
   /connectors/<name>/status` until connector *and every task* are
   `RUNNING`; a `FAILED` task's `trace` is the first thing to read, not the
   worker log.
5. **Prove the data**: run the repo's IVT — `checksum_src.sql` against the
   source and `checksum_sink.sql` against the staging DB, compare
   `COUNT`/`CHECKSUM_AGG` per table. Any `WHERE` in the source query must
   mirror the `FilterTimestamp` cutoff exactly, or the mismatch is yours.
6. **Update the README tables and the checklist**, then hand back with: the
   diff, the status output, the IVT comparison, and the new file name.

Never deploy to `prd` without the `uat` run of the same file passing steps
4–5 first, and confirm with the user before any `DELETE /connectors/…`,
offset reset, or `snapshot.mode` change — those replay or drop data.

## Traps this pipeline has already hit

- **Two sources into one topic.** `dbHRMI_Center` and `dbHRMI_Center_NBC`
  both route to `EEAS_SRC_DEBEZIUM_CDB_<table>`. Anything one connector
  injects (`AddField` → `IsDeleted`) the other must inject with the *same
  name*, and column nullability differs between the two DBs, so their
  subjects are set to `compatibility=NONE` (`scripts/set_compat_none.sh`).
  That leaves the JDBC sink's `auto.evolve=false` as the only schema gate —
  a new column needs the staging DDL first.
- **`FilterTimestamp` keeps what it can't read.** NULL, empty, or unparseable
  values pass; only parseable values before the cutoff drop. Count that way
  in the IVT `WHERE`.
- **Delete handling is per connector, not per table.** `hard_del` configs
  run tombstones on + `unwrap` drop + sink `delete.enabled=true`; everything
  else is soft (`__deleted` dropped). Putting a hard-delete table in a
  soft-delete connector silently keeps deleted rows.
- **SMT chain order is the listed order.** A rename after a filter that
  needed the original name breaks the filter without an error.
- **Secrets are in the JSON today** — SFTP private keys, passphrases, AES
  keys, SR passwords in scripts. Treat every config as sensitive: never
  paste one into a report or a commit message. The correct fix is a Connect
  config provider (`FileConfigProvider`/`EnvVarConfigProvider` per the
  Connect docs); raise it as a finding whenever you touch such a file.

## Debezium 1.x → 3.x migration (from the `upgrade-platform` diffs)

Property renames observed between the live 1.9 configs and the 3.4.1 set:

| 1.x | 3.x |
|---|---|
| `database.server.name` | `topic.prefix` |
| `database.dbname` | `database.names` |
| `database.history.*` (kafka.topic, bootstrap, producer/consumer SASL+SSL) | `schema.history.internal.*` |
| — | `database.encrypt` (must be set; SQL Server driver default flipped) |
| topic `<prefix>.dbo.<table>` | `<prefix>.<database>.dbo.<table>` — every `RegexRouter` regex gains the DB segment |
| SMT package `com.mfec.kbank.thairedcross…` | `org.mfec.kbank.thairedcross…` (house SMT jar rebuilt) |

Migrate by diffing the connector's own old/new pair, not from this table
alone — confirm each rename against the Debezium release notes for the
target version, and run the `validate` endpoint on the worker that carries
the new plugin before anything else.

## House SMTs

`org.mfec.kbank.thairedcross.connect.smt.centralize` — `FilterTimestamp`,
`DecryptField`, `AddField`, `AddToKey`, `AssignIf`, `ExtractCDC`,
`TimeZoneConverter`, `ConvertByteToString`. Specs, rationale, and the
deploy runbook live in the `kbank-redcross-connectsmt` repo under `docs/`;
read the spec before configuring one, the class name alone doesn't tell you
the field semantics.
