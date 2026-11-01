{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'), columns=['amount', 'label', 'flag'], quantiles=0, top_n=0
) }}
