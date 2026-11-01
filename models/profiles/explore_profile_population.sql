{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'),
    columns=['amount', 'label'],
    where='id <= 7',
    grouping_sets=[['country'], ['country', 'channel']],
    population=ref('explore_population'),
    population_group_by=['country'],
    population_where='keep'
) }}
