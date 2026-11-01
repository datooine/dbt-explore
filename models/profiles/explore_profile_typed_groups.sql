{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'), columns=['label'], group_by=['byte_value', 'amount', 'flag'], top_n=1
) }}
