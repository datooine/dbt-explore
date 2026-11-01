{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'),
    columns=['amount', 'label'],
    grouping_sets=[[], ['channel'], ['country', 'channel']]
) }}
