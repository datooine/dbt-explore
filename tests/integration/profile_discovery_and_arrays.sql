{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with expected_columns as (
    select column_name from unnest([
        'id', 'country', 'channel', 'amount', 'constant_numeric', 'big_numeric',
        'float_number', 'null_number', 'label', 'null_string', 'flag', 'calendar_date',
        'local_datetime', 'happened_at', 'local_time', 'byte_value', 'json_value',
        'geography_value', 'customer.id', 'customer.address.country',
        'customer.address.city', 'items', 'records'
    ]) as column_name
), profile as (select * from {{ ref('explore_profile_all') }}),
failures as (
    select concat(coalesce(e.column_name, p.column_name), ': discovered field set') as failure
    from expected_columns as e full outer join profile as p using (column_name)
    where e.column_name is null or p.column_name is null
    union all
    select concat(column_name, ': duplicate discovered field') from profile group by column_name having count(*) != 1
    union all
    select concat(column_name, ': nested leaf null semantics') from profile
    where (column_name = 'customer.id' and (non_null_count is distinct from 2 or distinct_count is distinct from 2))
        or (column_name = 'customer.address.country' and (non_null_count is distinct from 3 or distinct_count is distinct from 1))
        or (column_name = 'customer.address.city' and (non_null_count is distinct from 2 or distinct_count is distinct from 2))
    union all
    select 'items: persisted array structure' from profile
    where column_name = 'items' and (
        non_null_count is distinct from 8 or null_count is distinct from 0
        or empty_count is distinct from 5 or min_length is distinct from 0
        or max_length is distinct from 3 or avg_length is null or abs(avg_length - 0.75) > 1e-12
        or total_elements is distinct from 6 or distinct_count is not null
        or distinct_rate is not null or min_value is not null or max_value is not null
        or array_length(quantile_values) != 0 or array_length(top_values) != 0
    )
    union all
    select 'records: struct array boundary' from profile
    where column_name = 'records' and (
        empty_count is distinct from 6 or total_elements is distinct from 2
        or max_length is distinct from 1 or avg_length is null or abs(avg_length - 0.25) > 1e-12
    )
    union all
    select 'transient_items: view array semantics'
    from {{ ref('explore_profile_view') }} as p
    cross join (
        select countif(transient_items is null) as null_count,
            countif(array_length(transient_items) = 0) as empty_count,
            min(array_length(transient_items)) as min_length,
            max(array_length(transient_items)) as max_length,
            avg(array_length(transient_items)) as avg_length,
            coalesce(sum(array_length(transient_items)), 0) as total_elements
        from {{ ref('explore_view') }}
    ) as e
    where p.column_name = 'transient_items' and (
        p.null_count is distinct from e.null_count or p.empty_count is distinct from e.empty_count
        or p.min_length is distinct from e.min_length or p.max_length is distinct from e.max_length
        or (p.avg_length is null) != (e.avg_length is null)
        or abs(p.avg_length - e.avg_length) > 1e-12 or p.total_elements is distinct from e.total_elements
    )
    union all
    select concat(column_name, ': explicit parent selection and leaf exclusion')
    from {{ ref('explore_profile_selected') }}
    where column_name not in ('customer.id', 'customer.address.country', 'amount', 'label')
        or group_1_name is distinct from 'customer.address.country'
        or observation_count not in (1, 3)
    union all
    select 'selected: expected four columns in each of two groups'
    from (select 1)
    where (select count(*) from {{ ref('explore_profile_selected') }}) != 8
    union all
    select concat(column_name, ': automatic grouping exclusion')
    from {{ ref('explore_profile_auto_grouped') }}
    where column_name in ('country', 'channel', 'json_value', 'geography_value')
        or starts_with(column_name, 'customer.')
        or array_length(top_values) > 1
)
select * from failures
