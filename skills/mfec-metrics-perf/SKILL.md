---
name: mfec-metrics-perf
argument-hint: "[run label: R0|R1|R2a-c|R3a-c|R4|R5|R6|custom|observe <label>]"
description: Run, validate, and report a Debezium Oracle LogMiner CDC perf test for the BBL POC (Oracle 12.2 -> Debezium 2.7 -> Connect 7.6 -> Kafka, metrics via JMX exporter :9404 into Prometheus/Grafana or New Relic). Covers pre-flight, the R0-R6 load matrix (load/run.sh), passive observation of someone else's load (load/observe.sh), reconciliation, bottleneck attribution, abort rules, and the nine-number one-page deliverable. Use when asked to load-test or benchmark the BBL CDC pipeline, measure CDC latency/throughput/ceiling, read the dbz-oracle-perf dashboard or its New Relic port, decide where a CDC bottleneck is, or produce the perf report.
---

# MFEC BBL Debezium Oracle CDC perf test

The repo is `BBL/metrics-perf`. A run is not done when the loader exits — it
is done when the drain has finished, reconciliation shows **mismatch = 0**,
and the numbers land in the nine-number deliverable. Every run ends with
that proof, not with a `results/` folder.

`confluent-kafka-developer` owns generic Connect/producer semantics
(converters, `linger.ms`, `batch.size`, compression); `confluent-kafka-admin`
owns the broker/topics. Use the `debezium` skill for LogMiner property
semantics. This skill owns the test procedure and how to read its numbers.

## Step 0 — read the repo's own record first

- `RUNBOOK.md` — the authority: pre-flight table, test matrix, loader rules,
  watch order, attribution rules A-F, abort criteria, deliverable.
- `docs.md` (Thai) — panel-by-panel meaning, normal vs warning values, and
  the **POC baseline column** (measured on a 2-core box with Oracle, Kafka and
  Connect co-located — a baseline, not a production target). Also the New
  Relic setup, NRQL per panel, and alert conditions.
- `load/run.sh`, `load/observe.sh`, `load/0{0,1,2}_*.sql` — what actually runs.
- `oracle.json` — the connector under test (gitignored; contains DB creds —
  never paste it). `monitoring/` — exporter rules, Prometheus, Grafana
  `dbz-oracle-perf`. `newrelic/` — nri-prometheus + infra agent, NR dashboards,
  `DEBUG-QUERIES.md`.
- Existing `results/<label>/` dirs — prior runs; a reused run_id aborts.

## Prerequisites

- Connect container from `compose.yml` (`connect-prite`, REST on host `:8017`,
  JMX exporter `:9404`, raw JMX `:9999`) on external docker network `dc1`.
  It mounts `monitoring/jmx_prometheus_javaagent.jar` and `./connect/connect-smt`
  — **neither is in the repo**; supply them. Broker, Schema Registry,
  Prometheus and Grafana are not defined here either.
- Tools on the driver host: `bash`, `curl`, `jq`, `awk`, and `sqlplus` — or
  set `ORA_CONTAINER=<name>` to run sqlplus via `docker exec`.
- One-time Oracle setup, POC box only, as SYSDBA: `load/00_setup.sql`
  (grants, `DBZ_HEARTBEAT` canary table, `LOAD_RUN_LOG`), then
  `load/01_loader.sql` (`LOAD_RUN`, `LOAD_BIG_TXN`). `observe.sh` needs
  `GRANT ANALYZE ANY` in the real environment too.
- Scrape interval: RUNBOOK says **5s** on test day; `monitoring/prometheus.yml`
  ships 10s, `newrelic/nri-prometheus.yml` 15s. Set it before R0.

## Configure a run

Both scripts take connection settings from env; the in-script defaults embed a
POC host and password — **always override, never echo them into a report**:

| Env | Meaning |
|---|---|
| `DB`, `USR`, `PWD_` | Oracle EZConnect string, user, password |
| `ORA_CONTAINER` | run sqlplus inside this container instead of on host |
| `METRICS` | exporter URL (default `http://localhost:9404/metrics`) |
| `CONNECT`, `CONN` | Connect REST URL (default `:8017`) and connector name |
| `OUT` | results root (default `results`) |
| `RUN_ID` | override preset id (1..99); rows use ID range `id*1e8 .. (id+1)*1e8` |

Presets in `run.sh` (run_id, sessions, rows/session, commit_every, sleep_ms):

| Preset | Params | Purpose |
|---|---|---|
| R0 | 10, 1, 100000, 1000, 0 | smoke — reconciliation must be exact; nothing else runs until it passes |
| R1 | 11, 4, 150000, 10, 40 | steady state — **the latency number** (p50/p95/p99) |
| R2a/b/c | 21-23, 4, 125000, 1 / 100 / 10000, 0 | commit sweep: commit-bound vs parse-bound |
| R3a/b/c | 31-33, 1 / 4 / 16 sessions, 100, 0 (500k total) | concurrency — DBZ is one task, find the flattening |
| R4 | 40, 16, 312500, 1000, 0 | overload — **the ceiling** |
| R5 | 50, 1, 2000000 in one txn (`LOAD_BIG_TXN`) | heap per buffered row, time-to-first-event; OOM is a result |
| custom | `./run.sh custom <id> <sess> <rows> <commit> <sleep_ms>` | anything else |

R1 pacing is meant to be ~50% of R0's drain rate (RUNBOOK); the preset's
`sleep_ms=40` is fixed — recompute it if R0's rate differs. **R6 (catch-up:
pause the task 5 min mid-load) has no preset** — run a `custom` load and pause
/resume via `PUT $CONNECT/connectors/$CONN/pause|resume` by hand.

Order: R0, R1, R2, R3, R4, R6, R5. Every run ends with a drain plus 2 min
idle; drain time is a result. Raise Connect heap to `-Xmx4g` before R4/R5
(POC hit 86% of 2 GB).

## Pre-flight — nothing is inserted until every line is green

Work the 17-row table in RUNBOOK §1. The ones that void runs most often:

1. Connector and every task `RUNNING`, no restart in 10 min; snapshot completed,
   streaming connected.
2. Pipeline idle: ActiveTransactions=0, QueueRemaining=QueueTotal, event rate 0
   for 2 min.
3. Latency canary: `heartbeat.interval.ms=5000` + `heartbeat.action.query`
   updating `DBZ_HEARTBEAT`, and that table in `table.include.list`.
   **`oracle.json` today has neither** — add them or the canary latency number
   does not exist (confirm with the user before changing the live connector).
4. Oracle vs Connect clock offset < 100 ms; archivelog + supplemental logging on;
   redo log size recorded (<512 MB = switch churn); FRA headroom >= 30 GB.
5. Archive cleanup: only logs with `next_change# < OffsetScn`. Never above.
6. Config frozen: `run.sh` saves `connector.json` per run; record `-Xmx` and cores.

`run.sh` self-aborts if Oracle is unreachable, the connector/tasks are not
`RUNNING`, abandoned txns are already > 0, a loader session is still open in
`LOAD_RUN_LOG`, or the run_id range already holds rows.

## Execute

```bash
cd load
DB=... USR=... PWD_=... CONN=<connector> ./run.sh R0     # one run per call
RUN_ID=12 ./run.sh R1                                      # re-run under fresh id
DURATION=3600 ./observe.sh <label>                         # someone else's load; or Ctrl+C
```

Annotate run start/stop in Grafana. `run.sh` launches N sqlplus sessions,
aborts on any `ORA-|PLS-|SP2-|ERROR` in `session_*.log`, then drains: polls
`totalnumberofeventsseen` every 5s until unchanged for 12 polls (60s); drain
end = the last time the counter moved.

`observe.sh` (env adds `SCHEMA`, `TABLE_LIKE`, `EVERY`=15s, `DURATION`)
snapshots t0, samples to CSV, waits 60s on stop, snapshots t1, and reconciles
`dba_tab_modifications` insert/update/delete deltas against Debezium's
create/update/delete counters. It counts table-level rows only — undercounts
partitioned tables.

## Where results land

`results/<label>/` (gitignored):

| File | Content |
|---|---|
| `params.json` | label, run_id, sessions, rows, commit, sleep, start UTC |
| `params.json.done` | load_s, drain_s, oracle_rows, captured_inserts, mismatch, abandoned, errors |
| `counters.txt` | before/after DBZ counters, `scn_before/after` (observe: + redo bytes, commits, archived logs) |
| `metrics_{before,after,t0,t1}.prom` | full exporter scrapes |
| `connector.json` / `status_t*.json` | frozen config / task status |
| `session_<n>.log` | per-session loader output |
| `samples.csv`, `summary.txt` | observe.sh only: lag, queue, active txn, CPU, send rate per sample; reconciliation table |

Then run `sqlplus ... @02_reconcile.sql <run_id>` for Oracle row count, ID
range, per-session timing/SCNs/errors, and `v$sysstat` cost. Cross-check against
the Kafka topic end-offset delta (`kafka-topics`/consumer offsets — see
`confluent-kafka-admin`).

## Read the numbers

Validity first (docs.md §1): if reconciliation fails, read nothing else.

- **Must be 0:** mismatch, `abandonedtransactioncount` (silent data loss),
  `numberofoversizedtransactions`, `errorcount`, task-error totals.
- Rolled-back txns may rise (LogMiner sees the whole DB) — noise if mismatch=0.
- `Cumulative rows captured` dropping = task restart = all `Total*` reset =
  run void. Always use `increase()` / NR `derivative()`, never raw totals.
- `MilliSecondsBehindSource` freezes at the last row's lag when idle and
  excludes producer+broker time — pair it with the heartbeat canary.

Watch order every 30s (RUNBOOK §4): event rate vs loader rows/s -> lag ->
**QueueRemaining/QueueTotal (full vs empty is the primary fork)** -> task
state/errors -> heap/GC/active txns -> producer `bufferpool_wait_ratio`,
queue time, request latency, retry rate -> `ProcessCpuLoad` x cores ->
mining time budget (parse/processing/resultset-next ms/s, BatchSize,
LogSwitchCount) -> Oracle FRA, redo MB/s, DBZ session wait, DB CPU.

Attribute only on a window where lag rose >= 3 min:

| Rule | Signal | Bottleneck |
|---|---|---|
| A1 | queue full + (bufferpool wait > 0.05 or retries > 0 or latency climbing) | producer/broker/network |
| A2 | queue full + bufferpool ~0 + CPU x cores >= 1 + poll ~= write | Connect serialization (converter/SMT) |
| B | queue empty + processing >= 800 ms/s + CPU x cores >= 1 | Debezium mining thread (parse > 50% = redo SQL parse) |
| C | queue empty + resultset-next + fetch >= 600 ms/s + CPU low + BatchSize at max | Oracle LogMiner |
| C' | C + LogSwitchCount > 6/min | redo logs too small — environment, resize and rerun |
| D | loader below target, lag flat, queue empty | Oracle/loader ceiling — record no CDC number |
| E | low sawtooth events/s, sleep pinned max | adaptive back-off, not a bottleneck |
| F | R5: events ~0, active txns > 0, heap climbing | expected buffering |

Sanity: resultset_next + fetch + processing + sleep ~= 1000 ms/s. Processing
already includes parse — do not add them.

Thresholds stated in the repo: abort at heap > 90% or GC > 20% (not R5),
clock offset > 500 ms, FRA > 85%, paced run off target > 10%, Prometheus gap
> 2 scrapes, any ORA-00257/01654/30036/01555, negative lag, any task restart.
NR dashboards chart lag against a **2 s** target. docs.md alerts: lag > 30 s
for 5 min, `connected` = 0, heap > 90% for 5 min, abandoned/oversized > 0.

A **real ceiling** needs: lag rising at a stable slope >= 5 min, events/s
plateau within +/-10%, exactly one of A1/A2/B/C explaining a pinned queue, no
errors, heap sawtooth without upward trend, and a drain at ~plateau rate that
reconciles to 0. Ceiling = mean events/s over the plateau + its letter.

## New Relic instead of Prometheus

`cd newrelic && cp .env.example .env` (set `NEW_RELIC_LICENSE_KEY`; never
commit `.env`), `docker compose up -d`, `docker logs -f nri-prometheus` must
show no 401/403. Filter NRQL on `clusterName = 'bbl-cdc-poc'`. Exporter values
arrive as gauges: use `derivative(x, 1 second)`, not `rate()`. Before importing
any NR dashboard JSON, replace the hard-coded account id with yours
(`DEBUG-QUERIES.md`).

Two metric namespaces exist: this repo's `monitoring/jmx-connect.yml` emits
`debezium_oracle_<context>_<attr>` (used by the scripts, Grafana
`dbz-oracle-perf`, and the root `Debezium Oracle CDC perf (bbl-cdc-poc).json`);
the `newrelic/*.json` dashboards, `gf_db.json` and `dashboard-*.json` query
`debezium_metrics_*`, from an exporter config **not in this repo**. Check which
one is flowing (`DEBUG-QUERIES.md` §3) before trusting an empty panel.

## Deliverable — nine numbers, one page

1. R1 latency at ~50% ceiling: p50/p95/p99/max, canary vs MilliSecondsBehindSource
2. R4 sustained ceiling: events/s + MB/s + attribution letter
3. Drain rate after overload; minutes to catch up per 1M-row backlog
4. Throughput vs rows/commit (R2, 3 points)
5. Throughput vs concurrency (R3, 3 points) and where it flattens
6. R5: heap per 1M buffered rows, time-to-first-event, burst rate, or OOM threshold
7. R6 catch-up rate after a 5-min pause
8. Footprint at ceiling: Connect cores + heap, DB CPU, redo MB/s, FRA growth GB/h
9. Integrity: mismatch = 0 on every valid run; list aborted runs and why

Hand back the page with each number's source (`results/<label>/...` or the
dashboard window) and compare against the docs.md POC baseline (e.g. R1 p50
4.0 s / p95 7.3 s, avg 1,268 ev/s; R0 avg 1,589 ev/s). A number without a
passing reconciliation next to it is not reportable.

## Unknowns — say so, don't invent

- Where Prometheus/Grafana run and how they are deployed (no compose for them).
- Source of the `debezium_metrics_*` exporter config and the "supplied CSV
  collector" the NR baseline dashboard mentions (SCN gate, `V$THREAD`).
- How latency percentiles (p50/p95/p99) are computed for the report — no
  script computes them; derive from `samples.csv` or dashboard queries and
  state which.
- Production targets: only the 2 s lag line and POC baselines exist.
- No report template file; the format is RUNBOOK §6.
