# Relation profiling

`dbt_explore.profile_relation` generates a composable BigQuery SELECT statement.
It returns one row per selected field and grouping combination. Profiling runs
when BigQuery executes that statement; compilation only discovers metadata with
`adapter.get_columns_in_relation`.

```jinja
{{ dbt_explore.profile_relation(
    relation,
    columns=None,
    exclude_columns=None,
    where=None,
    group_by=None,
    grouping_sets=None,
    population=None,
    population_group_by=None,
    population_where=None,
    quantiles=4,
    extra_percentiles=None,
    top_n=10
) }}
```

## Inputs and selection

Use a physical dbt Relation, normally `ref('model')` or `source('name', 'table')`,
for `relation` and `population`. Tables and views are supported. Ephemeral
models, raw SQL, CTE names, and strings standing in for Relations are unsupported.
Materialize upstream models before compiling a profile that discovers their
schema. dbt parsing works without warehouse metadata and preserves `ref()`
dependencies; parsing is not a substitute for warehouse compilation.

`columns` and `exclude_columns` accept lists of resolvable field paths. Omitted
`columns` discovers every leaf recursively through STRUCT fields, stopping at
ARRAYs. Selecting a parent selects descendants; excluding a parent removes
descendants. Exclusions are applied after selection. Unknown paths and a
selection with no remaining fields raise compilation errors.

For `customer STRUCT<id STRING, address STRUCT<country STRING, city STRING>>`,
automatic discovery returns `customer.id`, `customer.address.country`, and
`customer.address.city`. For `items ARRAY<STRUCT<sku STRING>>`, it returns
`items`, without `items.sku`. Null STRUCT parents are evaluated through their
leaf expressions, just like non-null STRUCTs whose individual fields are null.

`where` and `population_where` are trusted SQL predicates without the `WHERE`
keyword. Each is applied to its own relation before aggregation. They are not
rewritten, synchronized, or sanitized; project authors provide valid expressions.

## Output schema

All rows in one statement share `profiled_at`. `min_value` and `max_value` are
serialized after ordering in the source type, so numeric values are not ordered
lexicographically. Output field order is not a row-order guarantee; add an
`ORDER BY` when consuming results.

| Field | BigQuery type | Meaning and null behavior |
| --- | --- | --- |
| `source_relation` | STRING | Fully qualified input relation identifier. |
| `profiled_at` | TIMESTAMP | `CURRENT_TIMESTAMP()` evaluated by the profiling statement. |
| `column_name` | STRING | Column name or dotted leaf path. |
| `column_type` | STRING | Discovered BigQuery data type, including ARRAY element structure. |
| `grouping_level` | STRING | Comma-separated participating dimensions; null for the total. |
| `grouping_flags` | JSON | Dimension-to-flag mapping: `0` participates, `1` is aggregated away; `{}` when ungrouped. |
| `group_N_name` | STRING | Requested dimension at position N; null when aggregated away. No pairs when ungrouped. |
| `group_N_value` | STRING | Serialized value for dimension N; null for an actual null or an omitted dimension. |
| `observation_count` | INT64 | `COUNT(*)` of filtered profile rows in this group. |
| `non_null_count` | INT64 | Number of non-null field expressions. |
| `null_count` | INT64 | Number of null field expressions. |
| `null_rate` | FLOAT64 | `SAFE_DIVIDE(null_count, observation_count)`; null on zero rows. |
| `distinct_count` | INT64 | Exact distinct non-null values for supported scalar types; null when unsupported. |
| `distinct_rate` | FLOAT64 | `SAFE_DIVIDE(distinct_count, non_null_count)`; null when undefined. |
| `population_count` | INT64 | Independently filtered population row count; null when absent or unmatched. |
| `min_value` | STRING | Typed minimum serialized to STRING (base64 for BYTES); null when unsupported or no non-null values. |
| `max_value` | STRING | Typed maximum serialized to STRING (base64 for BYTES); null when unsupported or no non-null values. |
| `mean` | FLOAT64 | Numeric arithmetic mean; null when unsupported or no non-null values. |
| `stddev` | FLOAT64 | Numeric sample standard deviation; null when unsupported or fewer than two non-null observations. |
| `zero_count` | INT64 | Numeric zeros; zero for no matches, null for nonnumeric fields. |
| `empty_count` | INT64 | Empty STRINGs, BYTES, or ARRAYs; zero for no matches, null otherwise. |
| `min_length` | INT64 | Minimum STRING character length, BYTES byte length, or ARRAY element count. |
| `max_length` | INT64 | Maximum applicable length. |
| `avg_length` | FLOAT64 | Mean applicable length, ignoring null values. |
| `total_elements` | INT64 | Sum of ARRAY lengths; zero when no elements, null for non-ARRAY fields. |
| `quantile_values` | ARRAY&lt;STRUCT&lt;percentile FLOAT64, value FLOAT64&gt;&gt; | Ordered approximate numeric quantile boundaries; empty when disabled, unsupported, empty, or all null. |
| `top_values` | ARRAY&lt;STRUCT&lt;rank INT64, value STRING, count INT64, frequency FLOAT64&gt;&gt; | Approximate non-null STRING/BOOL distribution; empty when disabled, unsupported, or no values. |

Length minima, maxima, and means are null when no non-null applicable values
exist. An applicable count is zero when no rows match, including empty input;
an inapplicable scalar metric is null. Distribution collections consistently
use empty typed arrays rather than null arrays.

### Type capabilities

| Input type | Metrics beyond null/non-null counts |
| --- | --- |
| INT64, FLOAT64, NUMERIC, BIGNUMERIC | Exact distinct, typed min/max, mean, sample standard deviation, zero count, approximate quantiles. |
| STRING | Exact distinct, min/max, character lengths, empty count, approximate top values. |
| BOOL | Exact distinct and approximate top values. |
| DATE, DATETIME, TIMESTAMP, TIME | Exact distinct and typed min/max. |
| BYTES | Exact distinct, typed min/max encoded as base64, byte lengths, empty count. |
| ARRAY | Empty count, element-count min/max/mean, total elements. Distinct count/rate are null. |
| Other scalar types | Counts plus only operations explicitly supported by the type capability implementation. |

Arrays are not unnested, including arrays of STRUCTs or arrays containing null
elements. BigQuery may normalize null arrays to empty arrays when storing tables
or materializing results. The profiler cannot recover a distinction the physical
input no longer preserves. Element nulls, where present in an input expression,
still contribute to `ARRAY_LENGTH`.

## Grouping and populations

Use either `group_by=['country', 'channel']` for observed combinations or
`grouping_sets=[[], ['country'], ['country', 'channel']]` for several levels.
An empty inner list represents the total. Paths must resolve to supported scalar
grouping types; ARRAYs, STRUCT parents, and unsupported grouping types are rejected.
Automatic column discovery excludes grouping paths unless `columns` explicitly
selects them.

Numbered output positions follow `group_by` order or first appearance across
`grouping_sets`. They remain stable for the whole invocation. Dimension names
retain dotted paths. Participating null dimensions retain their names and flag
`0`; omitted dimensions have null names and values and flag `1`. This preserves
the distinction between actual null keys and total rows. Grouping and population
joins use native values internally; only the final output converts them to
STRING. BYTES grouping values use base64.

An ungrouped empty relation returns one profile row per selected field with zero
observations. An empty grouped relation has no observed groups. An explicit
empty grouping set still returns its total rows.

`population` adds an independent `COUNT(*)`. Its optional grouping paths must
use the same names and compatible types in both relations and occur in every
profile grouping set. For example, a population grouped by `country` cannot be
combined with `grouping_sets=[[], ['country']]`. Omitted or empty population
grouping uses one global population count for every profile row. Population-only
arguments without `population` are rejected.

Population joins use null-safe equality and preserve unmatched profile groups,
whose `population_count` is null. A matching/global empty population count is
zero. Counts are independent of the selected field. There is no entity matching,
distinct-entity counting, or automatic coverage metric. Multiple observations
per population row may legitimately produce a ratio above one:

```sql
SAFE_DIVIDE(observation_count, population_count)
```

## Approximate distributions

`quantiles` is a non-negative integer interval count. Four intervals request
percentiles `0, 25, 50, 75, 100`; three request `0, 100/3, 200/3, 100`.
`extra_percentiles` accepts only integers from 0 through 100. Boundaries are
deduplicated and sorted. With extras, the `APPROX_QUANTILES` grid is divisible by
both the interval count and 100, preserving regular and extra boundaries without
interpolation. For example, three intervals plus p95 use a 300-interval grid.
With no extras, the configured interval count is used directly. `quantiles=0`
disables regular boundaries but still permits explicitly requested extras.
Approximate numeric results are represented as FLOAT64, so very precise decimal
and large integer values can lose precision in the returned distribution.

`top_n` is a non-negative integer. It limits the approximate top STRING/BOOL
values from `APPROX_TOP_COUNT`; zero disables the computation. Nulls are removed
from the actual input to this aggregate. Each item has a one-based `rank`, STRING
`value`, approximate INT64 `count`, and
`frequency=SAFE_DIVIDE(count, non_null_count)`. The denominator remains the full
non-null count, even when only a few top values are returned. Tied values and
approximation details should not be used as deterministic identities.

Counts, distinct counts, and applicable scalar statistics remain exact subject
to the source type's arithmetic. Approximate collections should be tested for
shape, ordering, bounds, and statistical expectations rather than exact interior
quantile boundaries or universal tie order.

## Adapter extension and performance

The public macro dispatches `profile_relation` in the `dbt_explore` namespace.
Add `<adapter>__profile_relation` with the same signature and output contract to
support another adapter. Keep adapter-specific metadata normalization, type
capabilities, SQL expressions, and grouping/distribution handling behind that
implementation. BigQuery internal helpers are implementation details, not a
stable public API. The default implementation permits metadata-free parsing and
raises an actionable unsupported-adapter error during execution.

BigQuery SQL uses filtered input, shared wide statistical aggregation, native
`GROUPING SETS`, and typed arrays of STRUCTs to normalize fields. Top values use
shared normalized non-null input. Population counts aggregate separately.
CTEs do not guarantee a particular physical scan count. Use the reproducible
benchmark in [CONTRIBUTING.md](../CONTRIBUTING.md) to inspect actual bytes,
slot time, and execution stages for a representative relation.

Version 0.1 does not provide ARRAY element profiling, raw SQL input, multiple
population scopes, drift detection, automated quality thresholds, or GA4 export
normalization. Persist profiles and calculate domain-specific ratios downstream.
