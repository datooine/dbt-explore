-- Opt in with dbt_explore_examples: true and supply an existing relation mapping.
{{ config(enabled=var('dbt_explore_examples', false)) }}

{% if var('dbt_explore_examples', false) %}
  {% set source = var('dbt_explore_example_relation') %}
  {% set relation = api.Relation.create(database=source['database'], schema=source['schema'], identifier=source['identifier'], type='table') %}
  {{ dbt_explore.profile_relation(relation=relation) }}
{% else %}
  SELECT CAST(NULL AS STRING) AS example_disabled WHERE FALSE
{% endif %}
