{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with profile as (select * from {{ ref('explore_profile_all') }}),
quantiles as (select * from {{ ref('explore_profile_quantiles') }}),
failures as (
    select concat(p.column_name, ': top values rank/count/denominator') as failure
    from profile as p cross join unnest(p.top_values) as value with offset position
    where value.rank is distinct from position + 1 or value.value is null
        or value.count <= 0 or value.count > p.non_null_count
        or value.frequency is distinct from safe_divide(value.count, p.non_null_count)
        or (position > 0 and value.count > p.top_values[offset(position - 1)].count)
    union all
    select 'label: null-heavy top values and ties'
    from profile
    where column_name = 'label' and (
        array_length(top_values) != 3
        or not exists (select 1 from unnest(top_values) where value = 'alpha' and count = 2 and frequency = 0.5 and rank = 1)
        or not exists (select 1 from unnest(top_values) where value = 'beta' and count = 1 and frequency = 0.25)
        or not exists (select 1 from unnest(top_values) where value = '' and count = 1 and frequency = 0.25)
    )
    union all
    select 'flag: boolean top values'
    from profile
    where column_name = 'flag' and (
        array_length(top_values) != 2
        or not exists (select 1 from unnest(top_values) where value = 'true' and count = 2 and frequency = 2.0 / 3)
        or not exists (select 1 from unnest(top_values) where value = 'false' and count = 1 and frequency = 1.0 / 3)
    )
    union all
    select 'quartiles: default boundary structure'
    from profile where column_name = 'amount' and (
        array_length(quantile_values) != 5
        or exists (select 1 from unnest(quantile_values) as q with offset position
            where abs(q.percentile - position * 25) > 1e-9 or q.value is null or q.value < -10 or q.value > 20)
        or quantile_values[safe_offset(0)].value is distinct from -10.0
        or quantile_values[safe_offset(4)].value is distinct from 20.0
    )
    union all
    select concat(scenario, '/', column_name, ': quantile boundaries/order/constant/all-null')
    from quantiles as p
    where
        (column_name = 'null_number' and array_length(quantile_values) != 0)
        or (column_name != 'null_number' and array_length(quantile_values) != case scenario when 'thirds' then 6 when 'deciles' then 11 else 2 end)
        or exists (
            select 1 from unnest(quantile_values) as q with offset position
            where q.value is null
                or (column_name = 'constant_numeric' and q.value != 7.5)
                or (column_name = 'amount' and (q.value < -10 or q.value > 20))
                or (position > 0 and (q.percentile <= p.quantile_values[offset(position - 1)].percentile
                    or q.value < p.quantile_values[offset(position - 1)].value))
                or (scenario = 'thirds' and abs(q.percentile - [0.0, 100.0 / 3, 50.0, 200.0 / 3, 95.0, 100.0][offset(position)]) > 1e-9)
                or (scenario = 'deciles' and abs(q.percentile - position * 10.0) > 1e-9)
                or (scenario = 'extras_only' and q.percentile != [50.0, 95.0][offset(position)])
        )
    union all
    select concat(column_name, ': disabled distributions')
    from {{ ref('explore_profile_no_distributions') }}
    where array_length(quantile_values) != 0 or array_length(top_values) != 0
    union all
    select 'top_n=1: global null-heavy input excludes nulls before approximation'
    from {{ ref('explore_profile_top_limit') }}
    where (column_name = 'label' and (array_length(top_values) != 1
        or top_values[safe_offset(0)].value is distinct from 'alpha'
        or top_values[safe_offset(0)].count is distinct from 2
        or top_values[safe_offset(0)].frequency is distinct from 0.5))
        or (column_name = 'null_string' and array_length(top_values) != 0)
        or array_length(top_values) > 1
    union all
    select 'top_n=1: nulls removed before approximation'
    from {{ ref('explore_profile_auto_grouped') }}
    where column_name = 'label' and group_1_value = 'ES' and group_2_value = 'web'
        and (array_length(top_values) != 1 or top_values[safe_offset(0)].value is distinct from 'alpha'
            or top_values[safe_offset(0)].count is distinct from 2)
)
select * from failures
