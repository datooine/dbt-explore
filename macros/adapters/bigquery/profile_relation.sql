{% macro bigquery__profile_relation(relation, columns=None, exclude_columns=None, where=None,
    group_by=None, grouping_sets=None, population=None, population_group_by=None,
    population_where=None, quantiles=4, extra_percentiles=None, top_n=10) %}
  {# Parse-time rendering must neither connect nor lose outer ref()/source() dependencies. #}
  {% if not execute %}{{ return('SELECT CAST(NULL AS STRING) AS column_name FROM (SELECT 1) WHERE FALSE') }}{% endif %}

  {% for name, value in [('columns', columns), ('exclude_columns', exclude_columns), ('group_by', group_by), ('population_group_by', population_group_by)] %}
    {% do dbt_explore._bq_profile_list(value, name) %}
  {% endfor %}
  {% for name, value in [('where', where), ('population_where', population_where)] %}
    {% if value is not none and (value is not string or not value | trim) %}{{ dbt_explore._bq_profile_error(name ~ ' must be a non-empty SQL predicate string, without WHERE.') }}{% endif %}
  {% endfor %}
  {% for name, value in [('quantiles', quantiles), ('top_n', top_n)] %}
    {% if value is boolean or value is not number or value != value | int or value < 0 %}{{ dbt_explore._bq_profile_error(name ~ ' must be a non-negative integer.') }}{% endif %}
  {% endfor %}
  {% set quantiles = quantiles | int %}{% set top_n = top_n | int %}
  {% set extras = extra_percentiles if extra_percentiles is not none else [] %}
  {% if extras is string or extras is mapping or extras is not sequence %}{{ dbt_explore._bq_profile_error('extra_percentiles must be a list of integers from 0 through 100.') }}{% endif %}
  {% for p in extras %}
    {% if p is boolean or p is not number or p != p | int or p < 0 or p > 100 %}{{ dbt_explore._bq_profile_error('extra_percentiles must contain only integers from 0 through 100.') }}{% endif %}
  {% endfor %}
  {% if group_by is not none and grouping_sets is not none %}{{ dbt_explore._bq_profile_error('group_by and grouping_sets are mutually exclusive.') }}{% endif %}
  {% if population is none and (population_group_by is not none or population_where is not none) %}{{ dbt_explore._bq_profile_error('population_group_by and population_where require a population relation.') }}{% endif %}
  {% if grouping_sets is not none %}
    {% if grouping_sets is string or grouping_sets is mapping or grouping_sets is not sequence or not grouping_sets %}{{ dbt_explore._bq_profile_error('grouping_sets must be a non-empty list of lists; use [[]] for the whole relation.') }}{% endif %}
    {% for item in grouping_sets %}
      {% if item is none %}{{ dbt_explore._bq_profile_error('grouping_sets entries must be lists; use [] for the whole relation.') }}{% endif %}
      {% do dbt_explore._bq_profile_list(item, 'grouping_sets') %}
    {% endfor %}
  {% endif %}
  {% set requested_sets = grouping_sets if grouping_sets is not none else [group_by if group_by is not none else []] %}
  {% set fields = dbt_explore._bq_profile_discover(relation) %}
  {% set dimensions = [] %}{% set dimension_names = [] %}{% set sets = [] %}{% set seen_sets = [] %}
  {% for requested in requested_sets %}
    {% set resolved = dbt_explore._bq_profile_resolve(requested, fields, 'grouping dimensions') %}
    {% if resolved | length != requested | length %}{{ dbt_explore._bq_profile_error('Grouping dimensions must not be repeated within a grouping set.') }}{% endif %}
    {% set indices = [] %}
    {% for field in resolved %}
      {% if field.family not in ['INT64', 'FLOAT64', 'NUMERIC', 'BIGNUMERIC', 'STRING', 'BOOL', 'BYTES', 'DATE', 'DATETIME', 'TIME', 'TIMESTAMP', 'INTERVAL'] %}{{ dbt_explore._bq_profile_error('Grouping requires a supported scalar, groupable path: ' ~ field.name ~ ' (' ~ field.type ~ ').') }}{% endif %}
      {% if field.name not in dimension_names %}{% do dimensions.append(field) %}{% do dimension_names.append(field.name) %}{% endif %}
      {% do indices.append(dimension_names.index(field.name)) %}
    {% endfor %}
    {% set key = indices | sort | join(',') %}
    {% if key in seen_sets %}{{ dbt_explore._bq_profile_error('Duplicate grouping sets are not supported.') }}{% endif %}
    {% do seen_sets.append(key) %}{% do sets.append(indices) %}
  {% endfor %}

  {% set selected = fields if columns is none else dbt_explore._bq_profile_resolve(columns, fields, 'columns', true) %}
  {% set excluded = dbt_explore._bq_profile_resolve(exclude_columns or [], fields, 'exclude_columns', true) %}
  {% set excluded_names = [] %}{% for field in excluded %}{% do excluded_names.append(field.name) %}{% endfor %}
  {% set profiled = [] %}
  {% for field in selected %}
    {% if field.name not in excluded_names and (columns is not none or field.name not in dimension_names) %}{% do profiled.append(field) %}{% endif %}
  {% endfor %}
  {% if not profiled %}{{ dbt_explore._bq_profile_error('No fields remain to profile after selection, exclusions, and grouping. Explicitly select grouping fields with columns if needed.') }}{% endif %}

  {% set population_dimensions = [] %}{% set population_indices = [] %}
  {% if population is not none %}
    {% set population_fields = dbt_explore._bq_profile_discover(population, 'population') %}
    {% set population_dimensions = dbt_explore._bq_profile_resolve(population_group_by or [], population_fields, 'population_group_by') %}
    {% if population_dimensions | length != (population_group_by or []) | length %}{{ dbt_explore._bq_profile_error('population_group_by must not contain duplicate dimensions.') }}{% endif %}
    {% for field in population_dimensions %}
      {% set ns = namespace(index=none) %}
      {% for dimension in dimensions %}
        {% if dimension.name | lower == field.name | lower %}
          {% if dimension.type != field.type %}{{ dbt_explore._bq_profile_error('Population grouping types must match: ' ~ field.name ~ ' (' ~ field.type ~ ' versus ' ~ dimension.type ~ ').') }}{% endif %}
          {% set ns.index = loop.index0 %}
        {% endif %}
      {% endfor %}
      {% if ns.index is none %}{{ dbt_explore._bq_profile_error('population_group_by must be a subset of profile grouping dimensions: ' ~ field.name) }}{% endif %}
      {% for grouping_set in sets %}
        {% if ns.index not in grouping_set %}{{ dbt_explore._bq_profile_error('Population grouping dimension ' ~ field.name ~ ' must be present in every profile grouping set.') }}{% endif %}
      {% endfor %}
      {% do population_indices.append(ns.index) %}
    {% endfor %}
  {% endif %}

  {% set grid = quantiles %}
  {% if extras %}
    {% set gcd = namespace(value=1) %}
    {% for divisor in range(1, 101) %}{% if quantiles % divisor == 0 and 100 % divisor == 0 %}{% set gcd.value = divisor %}{% endif %}{% endfor %}
    {% set grid = quantiles * 100 // gcd.value if quantiles else 100 %}
  {% endif %}
  {% set boundaries = [] %}
  {% if quantiles > 0 %}{% for i in range(quantiles + 1) %}{% do boundaries.append(i * grid // quantiles) %}{% endfor %}{% endif %}
  {% for p in extras %}{% do boundaries.append((p | int) * grid // 100) %}{% endfor %}
  {% set boundaries = boundaries | unique | sort | list %}
  {% set top_fields = [] %}
  {# Project to private aliases rather than appending to src.*: source columns
     may legitimately have the same names as our grouping/metric aliases. #}
  {% set source_profiled = profiled %}
  {% set profiled = [] %}
  {% for field in source_profiled %}
    {% do profiled.append({'name': field.name, 'type': field.type, 'family': field.family, 'sql': '__c' ~ loop.index0}) %}
  {% endfor %}
  {% if top_n > 0 %}{% for field in profiled %}{% if field.family in ['STRING', 'BOOL'] %}{% do top_fields.append(field) %}{% endif %}{% endfor %}{% endif %}

  {% set sql %}
WITH __dbe_source AS (
  SELECT * FROM {{ relation }}{% if where is not none %} WHERE {{ where }}{% endif %}
),
__dbe_input AS (
  SELECT TRUE AS __present, {% for field in source_profiled %}{{ field.sql }} AS __c{{ loop.index0 }}{% if not loop.last %}, {% endif %}{% endfor %}{% for field in dimensions %}, {{ field.sql }} AS __g{{ loop.index0 }}{% endfor %}
  FROM __dbe_source AS __src
),
__dbe_aggregated AS (
  SELECT
    {% for field in dimensions %}__g{{ loop.index0 }}, GROUPING(__g{{ loop.index0 }}) AS __f{{ loop.index0 }},{% endfor %}
    {% for field in profiled %}{{ dbt_explore._bq_profile_metric(field, grid) }} AS __m{{ loop.index0 }}{% if not loop.last %},{% endif %}{% endfor %}
  {# Anchor preserves an empty grand total even when BigQuery's GROUPING SETS
     yields no rows on empty input. Synthetic rows never contribute to counts. #}
  FROM (SELECT 1) AS __anchor LEFT JOIN __dbe_input ON TRUE
  {{ dbt_explore._bq_profile_grouping(sets) }}
  {% if dimensions %}
  HAVING COUNTIF(__present) > 0{% if [] in sets %} OR ({% for field in dimensions %}GROUPING(__g{{ loop.index0 }}) = 1{% if not loop.last %} AND {% endif %}{% endfor %}){% endif %}
  {% endif %}
),
__dbe_profiles AS (
  SELECT {% if dimensions %}__wide.* EXCEPT({% for field in profiled %}__m{{ loop.index0 }}{% if not loop.last %}, {% endif %}{% endfor %}), {% endif %}__metric.*
  FROM __dbe_aggregated AS __wide
  CROSS JOIN UNNEST([
    {% for field in profiled %}{{ dbt_explore._bq_profile_normalize('__m' ~ loop.index0, boundaries, grid) }}{% if not loop.last %},{% endif %}{% endfor %}
  ]) AS __metric
)
{% if top_fields %},
__dbe_top_input AS (
  SELECT {% for field in dimensions %}__g{{ loop.index0 }},{% endfor %} __entry.*
  FROM __dbe_input
  CROSS JOIN UNNEST([
    {% for field in top_fields %}STRUCT({{ dbt_explore._bq_profile_literal(field.name) }} AS __column_name, CAST({{ field.sql }} AS STRING) AS __value){% if not loop.last %},{% endif %}{% endfor %}
  ]) AS __entry
  WHERE __entry.__value IS NOT NULL
),
__dbe_top AS (
  SELECT __column_name,
    {% for field in dimensions %}__g{{ loop.index0 }}, GROUPING(__g{{ loop.index0 }}) AS __f{{ loop.index0 }},{% endfor %}
    APPROX_TOP_COUNT(__value, {{ top_n }}) AS __values
  FROM __dbe_top_input
  {% if not dimensions %}GROUP BY __column_name{% else %}{{ dbt_explore._bq_profile_grouping(sets, 1) }}{% endif %}
)
{% endif %}
{% if population is not none %},
__dbe_population AS (
  SELECT {% for field in population_dimensions %}{{ field.sql }} AS __p{{ loop.index0 }},{% endfor %} COUNT(*) AS population_count
  FROM {{ population }}
  {% if population_where is not none %}WHERE {{ population_where }}{% endif %}
  {% if population_dimensions %}GROUP BY {% for field in population_dimensions %}__p{{ loop.index0 }}{% if not loop.last %}, {% endif %}{% endfor %}{% endif %}
)
{% endif %}
SELECT
  {{ dbt_explore._bq_profile_literal(relation.database ~ '.' ~ relation.schema ~ '.' ~ relation.identifier) }} AS source_relation,
  CURRENT_TIMESTAMP() AS profiled_at,
  __profile.column_name,
  __profile.column_type,
  {% for field in dimensions %}
  IF(__profile.__f{{ loop.index0 }} = 0, {{ dbt_explore._bq_profile_literal(field.name) }}, CAST(NULL AS STRING)) AS group_{{ loop.index }}_name,
  IF(__profile.__f{{ loop.index0 }} = 0, {{ dbt_explore._bq_profile_string('__profile.__g' ~ loop.index0, field.family) }}, CAST(NULL AS STRING)) AS group_{{ loop.index }}_value,
  {% endfor %}
  {% if dimensions %}
  NULLIF(ARRAY_TO_STRING(ARRAY(
    SELECT __name FROM UNNEST([
      {% for field in dimensions %}IF(__profile.__f{{ loop.index0 }} = 0, {{ dbt_explore._bq_profile_literal(field.name) }}, CAST(NULL AS STRING)){% if not loop.last %},{% endif %}{% endfor %}
    ]) AS __name WITH OFFSET __position WHERE __name IS NOT NULL ORDER BY __position
  ), ','), '') AS grouping_level,
  JSON_OBJECT({% for field in dimensions %}{{ dbt_explore._bq_profile_literal(field.name) }}, __profile.__f{{ loop.index0 }}{% if not loop.last %}, {% endif %}{% endfor %}) AS grouping_flags,
  {% else %}CAST(NULL AS STRING) AS grouping_level, JSON '{}' AS grouping_flags,{% endif %}
  __profile.observation_count, __profile.non_null_count, __profile.null_count, __profile.null_rate,
  __profile.distinct_count, __profile.distinct_rate,
  {% if population is not none %}__population.population_count{% else %}CAST(NULL AS INT64){% endif %} AS population_count,
  __profile.min_value, __profile.max_value, __profile.mean, __profile.stddev, __profile.zero_count,
  __profile.empty_count, __profile.min_length, __profile.max_length, __profile.avg_length, __profile.total_elements,
  __profile.quantile_values,
  {% if top_fields %}
  ARRAY(
    SELECT AS STRUCT ROW_NUMBER() OVER (ORDER BY __top_value.count DESC, __top_value.value) AS rank,
      __top_value.value AS value, __top_value.count AS count,
      SAFE_DIVIDE(__top_value.count, __profile.non_null_count) AS frequency
    FROM UNNEST(__top.__values) AS __top_value
    ORDER BY __top_value.count DESC, __top_value.value
  )
  {% else %}CAST([] AS ARRAY<STRUCT<rank INT64, value STRING, count INT64, frequency FLOAT64>>){% endif %} AS top_values
FROM __dbe_profiles AS __profile
{% if top_fields %}
LEFT JOIN __dbe_top AS __top ON __profile.column_name = __top.__column_name
  {% for field in dimensions %}
  AND __profile.__g{{ loop.index0 }} IS NOT DISTINCT FROM __top.__g{{ loop.index0 }} AND __profile.__f{{ loop.index0 }} = __top.__f{{ loop.index0 }}
  {% endfor %}
{% endif %}
{% if population is not none %}
LEFT JOIN __dbe_population AS __population ON {% if not population_dimensions %}TRUE{% endif %}
  {% for index in population_indices %}
  {% if not loop.first %}AND {% endif %}__profile.__g{{ index }} IS NOT DISTINCT FROM __population.__p{{ loop.index0 }}
  {% endfor %}
{% endif %}
  {% endset %}
  {{ return(sql) }}
{% endmacro %}
