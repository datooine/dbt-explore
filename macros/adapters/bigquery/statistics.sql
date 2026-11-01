{% macro _bq_profile_metric(field, quantile_grid) %}
  {% set x = field.sql %}
  {% set family = field.family %}
  {% set numeric = family in ['INT64', 'FLOAT64', 'NUMERIC', 'BIGNUMERIC'] %}
  {% set distinct = numeric or family in ['STRING', 'BOOL', 'BYTES', 'DATE', 'DATETIME', 'TIME', 'TIMESTAMP', 'INTERVAL'] %}
  {% set ordered = numeric or family in ['STRING', 'BYTES', 'DATE', 'DATETIME', 'TIME', 'TIMESTAMP'] %}
  {% set length = ('ARRAY_LENGTH(' ~ x ~ ')') if family == 'ARRAY' else ('LENGTH(' ~ x ~ ')') %}
  STRUCT(
    {{ dbt_explore._bq_profile_literal(field.name) }} AS column_name,
    {{ dbt_explore._bq_profile_literal(field.type) }} AS column_type,
    COUNTIF(__present) AS observation_count,
    COUNTIF({{ x }} IS NOT NULL) AS non_null_count,
    COUNTIF(__present AND {{ x }} IS NULL) AS null_count,
    {% if distinct %}COUNT(DISTINCT {{ x }}){% else %}CAST(NULL AS INT64){% endif %} AS distinct_count,
    {% if ordered %}{{ dbt_explore._bq_profile_string('MIN(' ~ x ~ ')', family) }}{% else %}CAST(NULL AS STRING){% endif %} AS min_value,
    {% if ordered %}{{ dbt_explore._bq_profile_string('MAX(' ~ x ~ ')', family) }}{% else %}CAST(NULL AS STRING){% endif %} AS max_value,
    {% if numeric %}CAST(AVG({{ x }}) AS FLOAT64){% else %}CAST(NULL AS FLOAT64){% endif %} AS mean,
    {% if numeric %}CAST(STDDEV_SAMP({{ x }}) AS FLOAT64){% else %}CAST(NULL AS FLOAT64){% endif %} AS stddev,
    {% if numeric %}COUNTIF({{ x }} = 0){% else %}CAST(NULL AS INT64){% endif %} AS zero_count,
    {% if family in ['STRING', 'BYTES', 'ARRAY'] %}COUNTIF({{ length }} = 0){% else %}CAST(NULL AS INT64){% endif %} AS empty_count,
    {% if family in ['STRING', 'BYTES', 'ARRAY'] %}MIN({{ length }}){% else %}CAST(NULL AS INT64){% endif %} AS min_length,
    {% if family in ['STRING', 'BYTES', 'ARRAY'] %}MAX({{ length }}){% else %}CAST(NULL AS INT64){% endif %} AS max_length,
    {% if family in ['STRING', 'BYTES', 'ARRAY'] %}CAST(AVG({{ length }}) AS FLOAT64){% else %}CAST(NULL AS FLOAT64){% endif %} AS avg_length,
    {% if family == 'ARRAY' %}COALESCE(SUM({{ length }}), 0){% else %}CAST(NULL AS INT64){% endif %} AS total_elements,
    {% if numeric and quantile_grid > 0 %}APPROX_QUANTILES(CAST({{ x }} AS FLOAT64), {{ quantile_grid }} IGNORE NULLS){% else %}CAST([] AS ARRAY<FLOAT64>){% endif %} AS quantiles_raw
  )
{% endmacro %}

{% macro _bq_profile_normalize(alias, indices, grid) %}
  STRUCT(
    {{ alias }}.column_name AS column_name,
    {{ alias }}.column_type AS column_type,
    {{ alias }}.observation_count AS observation_count,
    {{ alias }}.non_null_count AS non_null_count,
    {{ alias }}.null_count AS null_count,
    SAFE_DIVIDE({{ alias }}.null_count, {{ alias }}.observation_count) AS null_rate,
    {{ alias }}.distinct_count AS distinct_count,
    SAFE_DIVIDE({{ alias }}.distinct_count, {{ alias }}.non_null_count) AS distinct_rate,
    {% for metric in ['min_value', 'max_value', 'mean', 'stddev', 'zero_count', 'empty_count', 'min_length', 'max_length', 'avg_length', 'total_elements'] %}
    {{ alias }}.{{ metric }} AS {{ metric }},
    {% endfor %}
    {% if indices %}
    ARRAY(
      SELECT AS STRUCT
        CAST(__index * 100.0 / {{ grid }} AS FLOAT64) AS percentile,
        {{ alias }}.quantiles_raw[SAFE_OFFSET(__index)] AS value
      FROM UNNEST([{{ indices | join(', ') }}]) AS __index
      WHERE ARRAY_LENGTH({{ alias }}.quantiles_raw) > 0
      ORDER BY __index
    )
    {% else %}CAST([] AS ARRAY<STRUCT<percentile FLOAT64, value FLOAT64>>){% endif %} AS quantile_values
  )
{% endmacro %}

{% macro _bq_profile_grouping(sets, offset=0) %}
  {% if sets | length == 1 and sets[0] | length == 0 %}{{ return('') }}{% endif %}
  {% set groups = [] %}
  {% for dimensions in sets %}
    {% set aliases = ['__column_name'] if offset else [] %}
    {% for dimension in dimensions %}{% do aliases.append('__g' ~ dimension) %}{% endfor %}
    {% do groups.append('(' ~ (aliases | join(', ')) ~ ')') %}
  {% endfor %}
  {{ return('GROUP BY GROUPING SETS (' ~ (groups | join(', ')) ~ ')') }}
{% endmacro %}
