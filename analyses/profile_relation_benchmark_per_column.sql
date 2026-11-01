-- Deliberately separate aggregate queries: the benchmark comparison baseline.
{{ config(enabled=var('dbt_explore_benchmark', false)) }}

{% if var('dbt_explore_benchmark', false) %}
  {% set source = var('dbt_explore_benchmark_relation') %}
  {% set relation = api.Relation.create(database=source['database'], schema=source['schema'], identifier=source['identifier'], type='table') %}
  {% for column in var('dbt_explore_benchmark_columns') %}
    {% if not loop.first %} UNION ALL {% endif %}
    SELECT * FROM (
      {{ dbt_explore.profile_relation(
          relation=relation,
          columns=[column],
          grouping_sets=var('dbt_explore_benchmark_grouping_sets', [[]]),
          where=var('dbt_explore_benchmark_where', none),
          quantiles=var('dbt_explore_benchmark_quantiles', 4),
          extra_percentiles=var('dbt_explore_benchmark_extra_percentiles', none),
          top_n=var('dbt_explore_benchmark_top_n', 10)
      ) }}
    )
  {% endfor %}
{% else %}
  SELECT CAST(NULL AS STRING) AS benchmark_disabled WHERE FALSE
{% endif %}
