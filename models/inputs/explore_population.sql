{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

select * from unnest([
    struct('ES' as country, true as keep),
    struct('ES', false),
    struct('US', true),
    struct(cast(null as string), true),
    struct(cast(null as string), true),
    struct('MX', true)
])
