{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with profile as (select * from {{ ref('explore_profile_all') }}),
failures as (
    select concat(column_name, ': universal counts/rates') as failure
    from profile
    where observation_count is distinct from 8
        or non_null_count + null_count is distinct from observation_count
        or null_rate is distinct from safe_divide(null_count, observation_count)
        or distinct_rate is distinct from safe_divide(distinct_count, non_null_count)
        or population_count is not null
        or grouping_level is not null
        or to_json_string(grouping_flags) != '{}'
    union all
    select 'amount: numeric statistics' from profile
    where column_name = 'amount' and (
        non_null_count is distinct from 4 or null_count is distinct from 4
        or distinct_count is distinct from 4 or min_value is distinct from '-10'
        or max_value is distinct from '20' or mean is null or abs(mean - 5) > 1e-9
        or stddev is null or abs(stddev - sqrt(500.0 / 3)) > 1e-9
        or zero_count is distinct from 1 or empty_count is not null
        or min_length is not null or total_elements is not null
    )
    union all
    select 'constant_numeric: constant statistics' from profile
    where column_name = 'constant_numeric' and (
        non_null_count is distinct from 8 or distinct_count is distinct from 1
        or mean is distinct from 7.5 or stddev is distinct from 0.0
        or zero_count is distinct from 0
    )
    union all
    select 'big_numeric: bignumeric support' from profile
    where column_name = 'big_numeric' and (
        non_null_count is distinct from 4 or mean is distinct from 1.5
        or distinct_count is distinct from 1 or zero_count is distinct from 0
    )
    union all
    select 'float_number: floating point support' from profile
    where column_name = 'float_number' and (
        non_null_count is distinct from 4 or mean is distinct from 1.25
        or min_value is distinct from cast(cast(0.5 as float64) as string)
        or max_value is distinct from cast(cast(2 as float64) as string)
    )
    union all
    select 'label: string statistics' from profile
    where column_name = 'label' and (
        non_null_count is distinct from 4 or distinct_count is distinct from 3
        or min_value is distinct from '' or max_value is distinct from 'beta'
        or empty_count is distinct from 1 or min_length is distinct from 0
        or max_length is distinct from 5 or avg_length is null or abs(avg_length - 3.5) > 1e-12
        or mean is not null or stddev is not null or zero_count is not null
        or total_elements is not null or array_length(quantile_values) != 0
    )
    union all
    select 'flag: boolean statistics' from profile
    where column_name = 'flag' and (
        non_null_count is distinct from 3 or distinct_count is distinct from 2
        or mean is not null or min_value is not null or max_value is not null
        or empty_count is not null or array_length(quantile_values) != 0
    )
    union all
    select 'byte_value: byte statistics' from profile
    where column_name = 'byte_value' and (
        non_null_count is distinct from 3 or distinct_count is distinct from 3
        or empty_count is distinct from 1 or min_length is distinct from 0
        or max_length is distinct from 2 or avg_length is null or abs(avg_length - 1.0) > 1e-12
        or min_value is distinct from to_base64(b'') or max_value is distinct from to_base64(b'c')
        or array_length(top_values) != 0
    )
    union all
    select concat(column_name, ': null-only statistics') from profile
    where column_name in ('null_number', 'null_string') and (
        non_null_count is distinct from 0 or null_count is distinct from 8
        or distinct_count is distinct from 0 or distinct_rate is not null
        or min_value is not null or max_value is not null or mean is not null
        or stddev is not null or array_length(quantile_values) != 0
        or array_length(top_values) != 0
        or (column_name = 'null_number' and zero_count is distinct from 0)
        or (column_name = 'null_string' and empty_count is distinct from 0)
    )
    union all
    select concat(column_name, ': unsupported scalar operations') from profile
    where column_name in ('json_value', 'geography_value') and (
        non_null_count is distinct from 2 or null_count is distinct from 6
        or distinct_count is not null or distinct_rate is not null
        or min_value is not null or max_value is not null or mean is not null
        or array_length(quantile_values) != 0 or array_length(top_values) != 0
    )
    union all
    {% for column in ['calendar_date', 'local_datetime', 'happened_at', 'local_time'] %}
    select '{{ column }}: temporal statistics' from profile
    where column_name = '{{ column }}' and (
        non_null_count is distinct from 2 or distinct_count is distinct from 2
        or min_value is distinct from (select cast(min({{ column }}) as string) from {{ ref('explore_fixture') }})
        or max_value is distinct from (select cast(max({{ column }}) as string) from {{ ref('explore_fixture') }})
        or mean is not null or min_length is not null
        or array_length(top_values) != 0 or array_length(quantile_values) != 0
    )
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)
select * from failures
