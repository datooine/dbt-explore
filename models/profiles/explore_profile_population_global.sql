{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'),
    columns=['amount', 'label'],
    where='id <= 4',
    group_by=['country'],
    population=ref('explore_population'),
    population_where='keep'
) }}
