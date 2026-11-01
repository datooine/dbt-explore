# Profiling benchmark: 2026-11-01

This measured BigQuery run compares one invocation profiling eight fields with a
`UNION ALL` of eight independent per-field invocations. The shared query produced
fewer execution stages and source-table read stages. Both shapes processed the
same reported bytes. Timing results on this small fixture do not establish a
general speed improvement.

The included [measurement summary](benchmarks/2026-11-01-core.json) includes all
six job IDs, exact timings, query hashes, configuration, and representative source
read steps. The complete local report, including every execution stage, is
generated at `target/benchmark/core-results.json`.

## Setup

- BigQuery project `bigquery-sandbox-cpvuft6h`, dataset `tmp`, EU location.
- dbt Core `1.12.6`, dbt-bigquery `1.12.1`, Python BigQuery client `3.47.0`.
- Input: 100,000 rows and 9,175,000 logical bytes, made by repeating the
  eight-row integration fixture 12,500 times. The data has deliberately low
  cardinality; it is a reproducible SQL-shape check, not a production workload.
- Fields: `amount`, `constant_numeric`, `big_numeric`, `float_number`, `label`,
  `flag`, `customer.id`, and `items`.
- Grouping sets: `[]`, `['country']`, `['country', 'channel']`.
- Defaults: four quantile intervals, no extra percentiles, ten top values, no
  filter or population. Each query returned 88 profile rows.
- Three repetitions per shape, alternating execution order, result cache
  disabled, and `maximum_bytes_billed=1000000000` for every job.

The benchmark table was created with a 24-hour expiration. Measurements completed
at 09:40 UTC on 2026-11-01. Its expiration was 09:39 UTC on 2026-11-02.

## Measured results

| Metric | Shared aggregation | Per-column UNION ALL |
| --- | ---: | ---: |
| Bytes processed, each execution | 5,750,000 | 5,750,000 |
| Bytes billed, each execution | 10,485,760 | 10,485,760 |
| Slot milliseconds, median | 6,924 | 7,259 |
| Client elapsed seconds, median | 3.452 | 1.669 |
| Execution stages, each execution | 10 | 50 |
| Source-table READ stages, each execution | 2 | 11 |
| Output rows, each execution | 88 | 88 |

| Repetition | Shared slot ms | Per-column slot ms |
| --- | ---: | ---: |
| 1 | 6,924 | 7,232 |
| 2 | 6,917 | 7,435 |
| 3 | 8,049 | 7,259 |

The shared plan read the source once for the wide statistical aggregate and once
for the combined STRING/BOOL top-value branch. The per-column plan contained
eight statistical source reads and three top-value source reads. Each source
read stage reported 100,000 input records. These counts come from `READ` steps
whose substeps explicitly identify the source table; shuffle reads are excluded.
BigQuery stages can read tables or shuffle data, so counting every `READ` step
would describe a different metric. See Google's
[query-plan explanation](https://docs.cloud.google.com/bigquery/docs/query-plan-explanation).

The shared median slot time was approximately 4.6% lower, while its observed
client elapsed time was higher. Reported bytes were equal despite the different
read-stage counts, and each baseline read projected only its required fields.
These measurements support the shared SQL shape's reduction in repeated source
read stages for this fixture. They do not show lower billed bytes or a reliable
latency advantage. Re-run on representative data before drawing a workload-level
performance conclusion.

## Reproduction

First materialize the integration input models using a profile pointing to the
sandbox dataset. Substitute your project/dataset and profile in both commands
when reproducing elsewhere:

```bash
uv run --locked --extra dev-v1 dbt run --select path:models/inputs \
  --profile default \
  --vars '{dbt_explore_integration_tests: true, dbt_explore_test_prefix: dbt_explore_}'
```

Create the benchmark relation with the BigQuery client or CLI. The statement
used for the measured run was:

```sql
CREATE OR REPLACE TABLE
  `bigquery-sandbox-cpvuft6h.tmp.dbt_explore_benchmark_input`
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
) AS
SELECT source.*
FROM `bigquery-sandbox-cpvuft6h.tmp.dbt_explore_explore_fixture` AS source
CROSS JOIN UNNEST(GENERATE_ARRAY(1, 12500)) AS replicate;
```

Its creation job used `maximum_bytes_billed=1000000000`, processed 734 bytes,
and consumed 964 slot milliseconds. The fixture-creation job is excluded from
the query comparison.

Run the benchmark with normal Application Default Credentials:

```bash
uv run --locked --extra dev-v1 --extra benchmark python scripts/benchmark.py \
  --relation bigquery-sandbox-cpvuft6h.tmp.dbt_explore_benchmark_input \
  --columns amount constant_numeric big_numeric float_number label flag customer.id items \
  --grouping-sets '[[],["country"],["country","channel"]]' \
  --location EU --repeats 3 --profile default \
  --maximum-bytes-billed 1000000000 \
  --output target/benchmark/core-results.json
```

The measured run selected the existing Core executable with `--dbt-command`;
the uv command above selects the locked Core environment instead. Dependency
updates or BigQuery optimizer changes can alter results. Benchmarks remain
outside routine CI.
