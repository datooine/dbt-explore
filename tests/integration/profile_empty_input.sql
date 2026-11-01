{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with failures as (
    select concat(column_name, ': empty ungrouped metrics') as failure
    from {{ ref('explore_profile_empty') }}
    where observation_count is distinct from 0 or non_null_count is distinct from 0
        or null_count is distinct from 0 or null_rate is not null or distinct_rate is not null
        or min_value is not null or max_value is not null or mean is not null or stddev is not null
        or min_length is not null or max_length is not null or avg_length is not null
        or array_length(quantile_values) != 0 or array_length(top_values) != 0
        or (column_name != 'items' and distinct_count is distinct from 0)
        or (column_name = 'amount' and zero_count is distinct from 0)
        or (column_name in ('label', 'items') and empty_count is distinct from 0)
        or (column_name = 'items' and total_elements is distinct from 0)
    union all
    select 'empty ungrouped: one row per column'
    from (select 1)
    where (select count(*) from {{ ref('explore_profile_empty') }}) != 3
    union all
    select 'empty grouped: no observed groups'
    from (select 1)
    where (select count(*) from {{ ref('explore_profile_empty_grouped') }}) != 0
    union all
    select 'empty grouping sets: explicit grand total survives'
    from (select 1)
    where (select count(*) from {{ ref('explore_profile_empty_sets') }}) != 1
    union all
    select 'empty grouping sets: grand total metadata'
    from {{ ref('explore_profile_empty_sets') }}
    where observation_count is distinct from 0 or grouping_level is not null
        or group_1_name is not null or group_1_value is not null
        or json_value(grouping_flags, '$.country') is distinct from '1'
)
select * from failures
