{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'),
    exclude_columns=['customer', 'json_value', 'geography_value'],
    group_by=['country', 'channel'],
    top_n=1
) }}
