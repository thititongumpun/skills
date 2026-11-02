---
name: mfec-hrdashboard
argument-hint: "[component: cdb | sftp-connector | ksql | validator | alert | ops-scripts] [env: dev|uat|prd]"
description: Change, deploy, and verify any part of the KBank Red Cross HR dashboard / EEAS data pipeline in ~/Desktop/mfec/hrdashboard — the Debezium CDB → dbEEAS_Stg path (jdbc/, EEAS_Artifacts/cdb), the HIS/HMIS SFTP invoice path (sftp-validator daemon → SFTP source connectors → ksqlDB → JDBC sink), the validator's Prometheus/Grafana alerting, and the kafka_operation_script deploy tooling, across dev/uat/prd. Use when adding a table or site, fixing a FAIL'd file, changing a validator env/pattern, redeploying a connector or ksql stream, checking why dbEEAS_Stg counts are off, or asked "what is running where" for this pipeline.
---

# MFEC HR dashboard (EEAS) pipeline

Several git repos sit side by side under `hrdashboard/`, and together they make one
pipeline into the staging DB `dbEEAS_Stg`. A change counts as done when the data
lands. A saved file or a restarted service doesn't prove that. Every loop below ends
with row counts, a `RUNNING` status, or a metric value.

Defer generic semantics to the other skills. `mfec-kafka-connect` covers house
connector conventions, the Debezium 1.x→3.x renames, the `FilterTimestamp` and
hard-delete traps, and the validate→diff→PUT→status loop. `confluent-kafka-developer`
covers connector, SMT and ksqlDB semantics. `confluent-kafka-admin` covers brokers,
Schema Registry, ACLs and topics. This skill only adds the map, the per-component
deploy routes and the proofs.

## Step 0 — read the repo's own record first

| What | Record of current state |
|---|---|
| PRD CDB + SFTP connector set, ksql, IVT | `EEAS_Artifacts/README.md`: tables of every connector, its tables, delete handling, filters and IVT pairing |
| Live connector inventory (all envs) | `upgrade-platform/connector_checklist_3.csv` (+ `connector_usage_checklist_20260804.xlsx`): name, state, class, Config Path Root, Current Version. Rows marked `**หา Config ไม่เจอ` ("config not found") are known gaps |
| Table scope for CDB | `jdbc/sync_new_db/lean/table.md` + `CHANGES.md` (28 tables in scope; 2 more come via SFTP) |
| SFTP validator | `sftp/CLAUDE.md` (architecture, env reference, metrics), `sftp/VALIDATE.md` (TRL spec), `sftp/ISSUES.md` (decisions) |
| Validator deployments | `sftp/deployments/DEPLOY.md` (service/dir/port/host per env), `sftp/deployments/alert.md` (scrape + alert rules) |
| Ops scripts | `kafka_operation_script/README.md` (Thai; per-script table) |
| HRDashboard DBSync pair | `docs/connector_DBSYNC_HRDASHBOARD_*_config.json` |

Then run `git -C <repo> log --oneline -10` and `git status` in the repo you'll touch.
`jdbc/` currently has uncommitted edits under `sync_new_db/lean/`. Don't build on
those until you know whose they are.

## The map

```
 CDB path (SQL Server CDC)
 dbHRMI_RC_NBC ─DBSYNC_HRDASHBOARD_SRC_DEBEZIUM─▶ SRC_DEBEZIUM_HRMI_dbo_<t> ─DBSYNC_HRDASHBOARD_SINK_JDBC─▶ dbHRMI_Center_NBC
 dbHRMI_Center, dbHRMI_Center_NBC, dbWorkforce, benefit
   ─EEAS_SRC_DEBEZIUM_CDB_<db>_<mst|txn>[_hard_delete]_*─▶ EEAS_SRC_DEBEZIUM_CDB_<table>
   ─(ksql: tbLearningEmp filter join)─▶ EEAS_SINK_JDBC_STG_dbEEAS_Stg[_hard_delete]_* ─▶ dbEEAS_Stg

 SFTP path (hospital invoice files), per site hiscuh | hisrcc | hmis
 /home/<site>/data[/<env>]/landing
   ─sftp-validator-<site>[_uat] (systemd, Python)─▶ PASS: TRL stripped → inbound, original → original/
                                                    FAIL: → error/ + <file>.html in meta_backup + MS Graph email
 inbound ─EEAS_SRC_SFTP_<SITE>_* (finished.path=archive, error.path=error, cleanup MOVE)─▶ EEAS_<SITE>_RAW_INVOICE
   ─ksql sftp_deploy.sql─▶ EEAS_<SITE>_TRANSFORMED_INVOICE ─EEAS_SINK_JDBC_STG_dbEEAS_Stg_FILE_*─▶ dbEEAS_Stg.{hisInvoice,hmisInvoice}
```

UAT SFTP topics carry a `UAT_` prefix and paths include `/uat/`. For dev, paths
include `/dev/`. Connector names in the checklist follow the naming scheme in
`mfec-kafka-connect`, e.g. `uat-eeas-src-sftp-hiscuh-…`.

## Components: where the code is, how it deploys

| Component | Source of truth | Deploy | Prove |
|---|---|---|---|
| CDB Debezium sources | prd: `EEAS_Artifacts/cdb/prd/src/`; uat: `EEAS_Artifacts/cdb/uat/src/` (Debezium 3.4 syntax); dev/uat versioned sets: `jdbc/DEV|UAT/version1_20260915/`, `upgrade-platform/{dev,uat}/` | Connect REST via ops scripts (below) | status + IVT checksum |
| CDB JDBC sinks | `EEAS_Artifacts/cdb/prd/sink/{sink,sink-hard-delete}.json` (pre-edit copies in `backup_20260914/`) | same | IVT checksum |
| CDB ksql | `EEAS_Artifacts/cdb/prd/src/ksql/tbLearningEmp{,_undeploy}.sql`, `cdb/uat/ksql/learning_*` | `run_script_ksql.sh` | `validate_sql_file.sh` → `RUNNING` |
| SFTP source connectors | `EEAS_Artifacts/sftp/{uat,prd}/src/config_<site>.json` (copies also in `sftp/configs/`) | ops scripts | file leaves `inbound` → `archive`; topic has records |
| SFTP ksql | `EEAS_Artifacts/sftp/{uat,prd}/ksql/sftp_{deploy,undeploy}.sql` | `set_compact_none.sh` (bash, not sh), then `run_script_ksql.sh` | streams `RUNNING` |
| SFTP sink | `EEAS_Artifacts/sftp/{uat,prd}/sink/sink.json` | ops scripts | `sftp/{uat,prd}/ivt/sftp_check_count.sql` |
| sftp-validator | `sftp/src/*.py`, per-site `sftp/.env.<site>[.uat|.prod]` | git pull/copy to `/home/admin/streamingdev[/uat]/<site>`, `make -f deployments/Makefile.<env> restart` | metrics + journal (below) |
| Validator alerting | `sftp/deployments/alert.md`, `grafana-secret-expiry-rule.js`, `sftp/dashboard/{db,db_prd}.json`, `dashboard/prometheus.yml` | Prometheus rule file + restart; Grafana rule via script | `/api/v1/targets` health, rule preview |
| Ops scripts | `kafka_operation_script/{CentOS,Ubuntu}/{UAT,PROD}/{Connect,ksqlDB}/` | copied to the Connect host | n/a, they're the tooling |
| House SMTs | `kbank-redcross-connectsmt/` (see `mfec-kafka-connect`) | jar on workers | `connector-plugins` lists the class |

## Change loop — connectors (CDB or SFTP)

1. Find the connector's row in `connector_checklist_3.csv`. Its `Config Path Root` /
   `Current Version` is the folder on the Connect host. The ops scripts read
   `connector_config/<root>/<version>/*.json` from their own directory.
2. Edit by adding a **new version folder or file**, never by overwriting. For a CDB
   table add, the four places listed in `mfec-kafka-connect` apply. Also update
   `lean/table.md`, and `checksum_src.sql`/`checksum_sink.sql` in both
   `EEAS_Artifacts/cdb/ivt/` and `jdbc/sync_new_db/`. The sink runs
   `auto.evolve=false`, so staging DDL goes first (`jdbc/sync_new_db/lean/sink_ddl/`).
3. Validate, then diff against live, following `mfec-kafka-connect` steps 2–3.
   `get_connector_config.sh` exists only under `PROD/`. On UAT use the REST GET.
4. Deploy from the Connect host. `cd kafka_operation_script/CentOS/<ENV>/Connect`,
   `source set_properties.sh`, then:
   - new: `sh create_connector.sh` or `deploy_all_connectors.sh` (POST)
   - update: `update_connector.sh` (PUT, **UAT only**; PROD has no update script, so
     confirm the route with the user)
   - inspect: `show_all_connector.sh`, `get_connector_status.sh`, `tail_connect_log.sh`
     (`/kafka_log/connect/connect.log`)
5. Prove it:
   - CDB: run `checksum_src.sql` on the source and `checksum_sink.sql` on
     `dbEEAS_Stg`, then compare COUNT/CHECKSUM_AGG per table. The scripted form is
     `jdbc/sync_new_db/cdb_to_stg/checksum_compare.sh`, which needs
     `SRC_IP SNK_IP DB_USER DB_PASS` in env. It prints `MATCH` or a diff. Use
     `cdb/ivt/full_config/` only against the `full_config/` connectors.
   - SFTP: run `sftp_check_count.sql` (section 2 splits `hisInvoice` by `source_db`).
     It counts distinct upserted invoices, not files.
6. Record what changed. Update the `EEAS_Artifacts/README.md` tables and the checklist
   row (state, version, config path). Hand back the diff, the status output, the IVT
   result, and the new file/version name.

## Change loop — ksqlDB streams

1. Schema change on SFTP streams: run `bash EEAS_Artifacts/sftp/<env>/set_compact_none.sh`
   first. It sets `NONE` on the six `EEAS_*_INVOICE` subjects only.
2. Run `*_undeploy.sql` (it drops transformed streams before raw), then `*_deploy.sql`,
   through `CentOS/<ENV>/ksqlDB/run_script_ksql.sh`. That logs to `log_files/` and
   calls `validate_sql_file.sh`.
3. Prove it: every stream named in the file shows `RUNNING` in the validate output,
   and the sink's IVT count moves. Dropping a CSAS replays from its offset policy, so
   confirm with the user before you undeploy in prd.

## Change loop — sftp-validator

1. **Code** (`sftp/src/`). There are no tests or linters. Test by pointing
   `SFTP_DATA_DIR` at a `sftp/data/case*` dir: `case1_pass_all` should PASS,
   `case6_fail_column_count_mismatch` should FAIL, and `newcase8_newreq` is the main
   TRL case. `sftp/unittest/<site>/` holds per-site samples. `case2`–`case7` are
   legacy and don't count. Check payloads against the connector schema with
   `python scripts/validate_schema.py <connector.json> <file>`.
2. **Config** (`.env.<site>[.uat|.prod]`). Keep `FILE_PATTERN` identical to the
   connector's `input.file.pattern` for that site and env. Keep `SFTP_INBOUND_DIR`
   equal to the connector's `input.path`. If either drifts, files pass validation
   and then sit in inbound, or go to `error`. Prd runs `RUN_MODE=cron` with
   `POLL_CRON_HOUR=23`. Dev and uat run `interval`. `ENV_MODE=prod` only in `.prod`
   files.
3. **Deploy** on the validator VM. Use the dir and service from the `DEPLOY.md`
   tables: dev/prd `sftp-validator-<site>`, uat `sftp-validator-<site>_uat`.
   Copy code or `git pull`. Run `pip install --no-index --find-links packages/` only
   if `requirements.txt` changed, since the hosts are offline. Then run
   `make -f deployments/Makefile.<dev|uat|prd> restart status` with `SITE_NAME` set
   for the site.
4. **Prove it**:
   - `curl -s localhost:<port>/metrics | grep -E 'sftp_last_poll_timestamp|sftp_files_validated_total'`.
     Ports: dev 9192–9194, uat 9195–9197, prd 9192–9194, in the order hiscuh/hisrcc/hmis.
     `sftp_last_poll_timestamp` must advance after the restart (prd cron: after 23:00).
   - `journalctl -u <service> -n 200` shows the poll and no reconnect loop.
     `logs/validation.log` gets one line per file.
   - End to end: drop a known-good file in `landing`. It should reach `inbound`, then
     `archive` once the connector picks it up, then the IVT count. Drop a bad file:
     it should reach `error/`, `<file>.html` should appear in `meta_backup`, and the
     email should arrive.

## Change loop — alerting

Prometheus scrape jobs are named `sftp-validator-<site>-<env>`. The rule
`SFTPValidatorDown` lives in `/etc/prometheus/rules/sftp-validator.yml`. The MS Graph
secret-expiry alert is a **Grafana** rule (`SFTPValidatorMailSecretExpiring`, < 30
days, to the Teams contact point). It reads `GRAPH_SECRET_EXPIRES` from each site's
`.env`. Prove it with the `alert.md` §4 verify loop: every target shows `"health": "up"`.
For the expiry rule, set a near date on a dev site, restart, see the Teams card, revert,
and see Resolved. When you rotate the Graph secret, update `GRAPH_CLIENT_SECRET` and
`GRAPH_SECRET_EXPIRES` in every site's `.env`, then restart all nine services.

## Housekeeping and reloads

`EEAS_Artifacts/sftp/housekeeping/` (mirrored in `sftp/scripts/` and `sftp/housekeeping/`,
documented in `sftp/scripts/DOCS.md`):
- `archive_data_monthly.sh` runs on the 1st of the month.
- `reload_data[_by_month].sh` moves archived files back to `inbound`. The sink upserts
  by key, so a reload overwrites rows and doesn't add any. Confirm the month range
  with the user before running a reload in prd.

## Guardrails

- Never deploy to `prd` before the same file or version passes the proof steps in `uat`.
- Get the user's OK first before any of these: connector DELETE, offset or snapshot
  change, ksql undeploy in prd, `delete_schema_with_prefix.sh` / `jdbc/delete_schema.sh`,
  topic deletes (`jdbc/cdc/cmd.txt`), `truncate_sink.sql`, `drop_*_tables.sql`.
- **Secrets sit in the repos. Never copy them into reports, commits, or this skill.**
  Point to the file or variable instead:
  - `sftp/.env*`: SFTP and `GRAPH_CLIENT_SECRET`, tracked in git
  - `sftp/encrypt_key/*`: tracked
  - `kafka_rsa_key` in `sftp/scripts/` and `sftp/housekeeping/`: tracked
  - `KAFKA_ADMIN`/`KAFKA_PASSWD` in `kafka_operation_script/**/set_properties*.sh`
  - `jdbc/delete_schema.sh` and `jdbc/cdc/cmd.txt`: inline SR, VM and SFTP passwords
  - `EEAS_Artifacts/sftp/*/src/config_hmis.json`: SFTP key, passphrase, AES key
  - `set_compact_none.sh`: SR password
  - the git remotes of `jdbc`, `kafka_operation_script` and
    `redcross-connector-config-converter` embed credentials

  Raise this as a finding whenever you touch one of these files. The fix is the one
  `mfec-kafka-connect` recommends: a config provider or env vars.

## Known gaps (verify before relying on them)

- The prd validator host differs between docs. `DEPLOY.md` says `TPRDLRC301`,
  `alert.md` says `TUATLRPRDC301`. Ask which one is right.
- The `Downstream` section of `sftp/CLAUDE.md` names topic `sftp-poc-trc` and
  `configs/cn-csv-manual.json`. Both look stale next to `EEAS_Artifacts`. Trust the
  `EEAS_Artifacts` configs.
- `EEAS_Artifacts` and `jdbc/` overlap. No file says which one is canonical for uat/dev.
- Many EEAS dev/uat Debezium rows in the checklist have no config path, and dev EEAS
  connectors show `PAUSED`.
- The dashboard that reads `dbEEAS_Stg` isn't in these repos, nor is its refresh
  path. "EEAS" is never expanded.
- No CI/CD exists for any component. `migration-cp/` (CP upgrade) and `docs/*.docx`
  are binary only and were not read.
