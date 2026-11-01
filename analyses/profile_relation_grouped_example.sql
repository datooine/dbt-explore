-- Grouping paths must exist in dbt_explore_example_relation.
{{ config(enabled=var('dbt_explore_examples', false)) }}

{% if var('dbt_explore_examples', false) %}
  {% set source = var('dbt_explore_example_relation') %}
  {% set relation = api.Relation.create(database=source['database'], schema=source['schema'], identifier=source['identifier'], type='table') %}
  {{ dbt_explore.profile_relation(
      relation=relation,
      columns=var('dbt_explore_example_columns', none),
      grouping_sets=var('dbt_explore_example_grouping_sets', [[]]),
      quantiles=4,
      extra_percentiles=[95, 99]
  ) }}
{% else %}
  SELECT CAST(NULL AS STRING) AS example_disabled WHERE FALSE
{% endif %}
