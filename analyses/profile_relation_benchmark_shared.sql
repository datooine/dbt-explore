-- Compiled by scripts/benchmark.py against an existing physical relation.
{{ config(enabled=var('dbt_explore_benchmark', false)) }}

{% if var('dbt_explore_benchmark', false) %}
  {% set source = var('dbt_explore_benchmark_relation') %}
  {% set relation = api.Relation.create(database=source['database'], schema=source['schema'], identifier=source['identifier'], type='table') %}
  {{ dbt_explore.profile_relation(
      relation=relation,
      columns=var('dbt_explore_benchmark_columns'),
      grouping_sets=var('dbt_explore_benchmark_grouping_sets', [[]]),
      where=var('dbt_explore_benchmark_where', none),
      quantiles=var('dbt_explore_benchmark_quantiles', 4),
      extra_percentiles=var('dbt_explore_benchmark_extra_percentiles', none),
      top_n=var('dbt_explore_benchmark_top_n', 10)
  ) }}
{% else %}
  SELECT CAST(NULL AS STRING) AS benchmark_disabled WHERE FALSE
{% endif %}
