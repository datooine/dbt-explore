# dbt-explore — Reusable exploratory SQL

**The SQL you keep rewriting, packaged.**

dbt-explore generates composable profiling queries for BigQuery. Profile scalar
columns, nested STRUCT leaves, and ARRAY structure, with dynamic grouping,
approximate distributions, and optional population counts.

Version `0.1.0` supports BigQuery on dbt Core and dbt v2. The package declares
`>=1.6.0,<3.0.0`; development and CI pin their runtime versions in `uv.lock`.
Public macros use adapter dispatch so additional warehouses can be implemented
without changing callers.

## Installation

Add the repository to your dbt project's `packages.yml`, then run `dbt deps`:

```yaml
packages:
  - git: https://github.com/datooine/dbt-explore.git
    revision: 0.1.0
```

Use a released tag that exists in the repository, or pin a commit when testing
an unreleased version.

## profile_relation

Use a dbt Relation from `ref()` or `source()`. The source table or view must
already exist when the model is compiled because column discovery reads
warehouse metadata.

```jinja
{{ dbt_explore.profile_relation(relation=ref('orders')) }}
```

The macro returns a SELECT statement, with one row for each selected column and
observed grouping combination. Put it directly in a model or inside a CTE:

```jinja
with profile as (
    {{ dbt_explore.profile_relation(
        relation=ref('orders'),
        columns=['amount', 'status', 'customer'],
        exclude_columns=['customer.address.city'],
        where="order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)",
        grouping_sets=[[], ['country'], ['country', 'channel']],
        quantiles=4,
        extra_percentiles=[95, 99],
        top_n=10
    ) }}
)
select * from profile
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `relation` | required | Physical dbt Relation: table or view. |
| `columns` | `None` | List of column or dotted field paths; parent paths select descendants. |
| `exclude_columns` | `None` | Paths excluded after selection; parent paths exclude descendants. |
| `where` | `None` | Trusted SQL predicate, without `WHERE`, applied before aggregation. |
| `group_by` | `None` | List of scalar grouping paths. |
| `grouping_sets` | `None` | List of grouping-path lists; `[]` inside the list requests the total. |
| `population` | `None` | Optional physical Relation supplying independent row counts. |
| `population_group_by` | `None` | Population grouping paths; omitted means one global count. |
| `population_where` | `None` | Independent trusted population predicate. |
| `quantiles` | `4` | Non-negative integer interval count; zero disables regular boundaries. |
| `extra_percentiles` | `None` | Additional integer boundaries from 0 through 100. |
| `top_n` | `10` | Maximum frequent STRING/BOOL values; zero disables top values. |

`group_by` and `grouping_sets` are mutually exclusive. Automatic discovery omits
grouping dimensions; include them in `columns` to profile them explicitly.
STRUCT discovery stops at ARRAY boundaries: `ARRAY<STRUCT<...>>` is one
structurally profiled field, with no automatic element-level profiling.

### Grouping output

Grouping dimensions use numbered STRING pairs, rather than source column names:
`group_1_name`, `group_1_value`, `group_2_name`, `group_2_value`, and so on.
For `group_by`, positions follow caller order. For `grouping_sets`, positions
follow first appearance across the requested sets and stay fixed in every row.
Names preserve dotted field paths. BYTES values use base64; other supported
grouping values use BigQuery's string representation.

For `grouping_sets=[[], ['country'], ['country', 'channel']]`:

| Grouping level | group_1_name | group_1_value | group_2_name | group_2_value |
| --- | --- | --- | --- | --- |
| `NULL` | `NULL` | `NULL` | `NULL` | `NULL` |
| `country` | `country` | `ES` | `NULL` | `NULL` |
| `country,channel` | `country` | `ES` | `channel` | `web` |
| `country,channel` | `country` | `NULL` | `channel` | `web` |

The last row represents an actual null country. Its name remains `country` and
`grouping_flags` contains `"country": 0`. An aggregated-away country has both
pair fields null and a flag of `1`. Ungrouped invocations emit no numbered pairs.

### Population counts

```jinja
{{ dbt_explore.profile_relation(
    relation=ref('ga4_parameters'),
    columns=['value'],
    group_by=['event_name', 'parameter_name'],
    population=ref('ga4_events'),
    population_group_by=['event_name']
) }}
```

`observation_count` counts profile rows and `population_count` counts population
rows. Compute ratios downstream with `SAFE_DIVIDE`. Counts do not join entity
IDs, and a ratio may exceed one. Population paths must have compatible types in
both relations and participate in every requested profile grouping set. A missing
population group returns null; an ungrouped empty population returns zero.

## Output and semantics

All output fields, types, supported metrics, null behavior, validation rules,
and adapter extension points are documented in
[docs/profiling.md](docs/profiling.md).

- Counts and distinct counts are exact where supported; quantiles and top values
  are approximate. Top-value frequencies use non-null observations.
- Unsupported scalar metrics return `NULL`; distributions return `[]`.
- Numeric empty/all-null inputs return `[]` quantiles. Zero denominators yield
  null rates. `profiled_at` is the query's `CURRENT_TIMESTAMP()`.
- Null and empty arrays may become indistinguishable after BigQuery stores or
  materializes them. ARRAY metrics describe the values the input relation exposes.
- The macro generates one query and reads schema metadata during compilation;
  it never runs the profiling query during compilation.

See [analyses/](analyses/) for opt-in examples and a reproducible benchmark
comparing shared aggregation with per-column queries. A measured 100,000-row
comparison is recorded in [docs/benchmark.md](docs/benchmark.md). Development, BigQuery
integration tests, CI, and benchmark instructions are in
[CONTRIBUTING.md](CONTRIBUTING.md).
