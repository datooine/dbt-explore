# Contributing

## Local setup

Use Python 3.12 or later and uv. Default development uses dbt v2:

```bash
uv sync --locked --extra dev
```

Configure a `dbt_explore` BigQuery profile in `~/.dbt/profiles.yml`:

```yaml
dbt_explore:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: your-gcp-project
      dataset: dbt_explore_dev
      location: EU
      threads: 1
```

Use Application Default Credentials for local OAuth, for example through
`gcloud auth application-default login`. The account needs permission to run
BigQuery jobs and create fixture tables/views in the development dataset. dbt v2
also needs BigQuery Read Session User (`roles/bigquery.readSessionUser`). Use
`DBT_PROFILES_DIR` or `--profiles-dir` for another profile location, and pass
`--profile name` to reuse a profile with a different name.

## Runtime compatibility and integration tests

| Extra | Runtime | Purpose |
| --- | --- | --- |
| `dev` | dbt v2 (`dbt`) | Default development and documentation generation. |
| `dev-v2` | dbt v2 (`dbt`) | Explicit v2 CI selection. |
| `dev-v1` | dbt Core (`dbt-core`, `dbt-bigquery`) | Core compatibility checks. |
| `benchmark` | Python BigQuery client | Optional benchmark execution; combine with one runtime extra. |

Select one runtime extra at a time: both runtimes provide the `dbt` executable.
The package compatibility range is `>=1.6.0,<3.0.0`; the lockfile records the
specific development and CI versions. Package consumers use their own dbt
installation and connection profile.

Run credential-free compatibility checks from the repository root:

```bash
uv run --locked --extra dev-v1 python scripts/check_compatibility.py
uv run --locked --extra dev-v2 python scripts/check_compatibility.py
```

Run actual BigQuery integration tests separately for each runtime:

```bash
uv run --locked --extra dev-v1 ./scripts/run_integration_tests.sh
uv run --locked --extra dev-v2 ./scripts/run_integration_tests.sh
```

The runner materializes fixture models in `models/inputs` before compiling
profiling models in `models/profiles`, then executes the models and singular SQL
assertions. It forwards additional dbt arguments,
such as `--profile your_existing_profile`. Fixtures and test models are disabled
by default; the runner enables `dbt_explore_integration_tests`. Set
`DBT_EXPLORE_TEST_PREFIX` or the `dbt_explore_test_prefix` dbt variable to isolate
relations. CI supplies a unique prefix; concurrent manual runs should also use
distinct prefixes, including a trailing underscore.

The warehouse tests cover scalar and nested discovery, ARRAY structure, selection
and exclusions, filters, actual null grouping keys, grouping sets, empty input,
population scopes, distributions, and statement timestamps. Approximate outputs
are checked through structure and appropriate statistical expectations. Offline
checks cover warehouse-free parsing, dependency preservation, and unsupported
adapter errors; they do not establish BigQuery SQL correctness.

To regenerate documentation after fixtures exist:

```bash
uv run --locked --extra dev dbt docs generate
```

Use `uv lock --upgrade-package dbt` to update v2, or
`uv lock --upgrade-package dbt-core --upgrade-package dbt-bigquery` for Core.
Commit `uv.lock` with dependency changes. Keep package versions in
`dbt_project.yml`, `pyproject.toml`, and `uv.lock` aligned for a release.

## Example analyses

Examples are opt-in because they discover metadata from an existing table or
view. Supply the relation as a mapping with `database`, `schema`, and `identifier`:

```bash
uv run --locked --extra dev dbt compile --select profile_relation_example \
  --vars '{dbt_explore_examples: true, dbt_explore_example_relation: {database: your-project, schema: analytics, identifier: orders}}'
```

`profile_relation_example` profiles all eligible fields.
`profile_relation_grouped_example` additionally takes
`dbt_explore_example_columns` and `dbt_explore_example_grouping_sets`:

```bash
uv run --locked --extra dev dbt compile --select profile_relation_grouped_example \
  --vars '{dbt_explore_examples: true, dbt_explore_example_relation: {database: your-project, schema: analytics, identifier: orders}, dbt_explore_example_columns: [amount, status], dbt_explore_example_grouping_sets: [[], [country], [country, channel]]}'
```

Compiled analyses are written beneath `target/compiled/dbt_explore/analyses/`.
Use `dbt show --select ...` with the same variables to execute an analysis.

## Reproducible performance benchmark

Benchmarks are excluded from routine CI. Use a representative existing relation
with multiple fields and grouping levels. The runner compiles two analyses with
the same options: one macro invocation profiling every selected field, and a
`UNION ALL` of independent per-column invocations. It executes both with result
caching disabled, alternates their order across repetitions, and records job
IDs, bytes processed/billed, slot milliseconds, elapsed time, output row counts,
and BigQuery execution stages. Source data is never created or modified.

```bash
uv run --locked --extra dev --extra benchmark python scripts/benchmark.py \
  --relation your-project.analytics.orders \
  --columns amount status customer.id \
  --grouping-sets '[[], ["country"], ["country", "channel"]]' \
  --location EU --repeats 3 \
  --output target/benchmark/results.json
```

Use `--profile`, `--profiles-dir`, and `--target` for dbt profile selection.
The Python client uses Application Default Credentials, including
`GOOGLE_APPLICATION_CREDENTIALS` when configured. Both dbt and the client must
have access to the same relation. `--project` overrides the client's billing/job
project. Use `--maximum-bytes-billed` to cap each executed job, `--dry-run` for
byte estimates without executing queries, or `--compile-only` to inspect the SQL.

The JSON report includes query hashes, the full selected configuration, runtime
version, and per-job stage data so results can be compared and reproduced.
Dry-run results explicitly have no execution or slot measurements. A report
without execution does not satisfy the warehouse performance acceptance check.

Inspect physical execution stages instead of assuming a CTE implies one scan.
Compare byte totals and slot time together; normalized top-value input and
different field types can change execution plans. Record the dataset size,
runtime, date, report, and observations when publishing benchmark results.
No performance numbers are asserted without a measured BigQuery report.
The [2026-11-01 benchmark](docs/benchmark.md) records an executed 100,000-row
comparison, including bytes, slot time, source reads, and its practical limits.

## CI credentials and releases

Warehouse CI uses project `bigquery-sandbox-cpvuft6h`, dataset `tmp`, EU location,
and the Actions secret `DBT_BIGQUERY_CI_SERVICE_ACCOUNT_JSON_BASE64`. Enable
repository access to that organization secret. The service account needs job
execution, fixture creation permissions, and the dbt v2 read-session role.
CI decodes the key on the runner without printing it, then creates a profile
selected through `DBT_PROFILES_DIR`.

The workflow follows dbt-event-patterns: credential-free compatibility checks,
a Core/v2 warehouse matrix, GitHub Pages documentation on `main`, and tagging
from the version in `dbt_project.yml` after prerequisite checks pass. Configure
GitHub Pages to use GitHub Actions before expecting publication. Fixture names
include the package, CI run, and runtime so parallel runs do not collide.

To exercise the workflow locally with Docker and
[act](https://github.com/nektos/act), pass the same secret and use
`-P ubuntu-latest=catthehacker/ubuntu:act-latest`. The `nektos/act` actor skips
documentation publication and release tags. Credential-free jobs can run without
supplying a service-account secret. Never commit keyfiles or benchmark credential
contents.
