{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

{% set all_profile = ref('explore_profile_all') %}
{% set grouped_profile = ref('explore_profile_grouped') %}
{% set empty_profile = ref('explore_profile_empty') %}
{% set fixture = ref('explore_fixture') %}

with common_columns as (
    select * from unnest([
        struct('source_relation' as column_name, 'STRING' as data_type),
        struct('profiled_at', 'TIMESTAMP'), struct('column_name', 'STRING'), struct('column_type', 'STRING'),
        struct('grouping_level', 'STRING'), struct('grouping_flags', 'JSON'),
        struct('observation_count', 'INT64'), struct('non_null_count', 'INT64'), struct('null_count', 'INT64'),
        struct('null_rate', 'FLOAT64'), struct('distinct_count', 'INT64'), struct('distinct_rate', 'FLOAT64'),
        struct('population_count', 'INT64'), struct('min_value', 'STRING'), struct('max_value', 'STRING'),
        struct('mean', 'FLOAT64'), struct('stddev', 'FLOAT64'), struct('zero_count', 'INT64'),
        struct('empty_count', 'INT64'), struct('min_length', 'INT64'), struct('max_length', 'INT64'),
        struct('avg_length', 'FLOAT64'), struct('total_elements', 'INT64'),
        struct('quantile_values', 'ARRAY<STRUCT<percentile FLOAT64, value FLOAT64>>'),
        struct('top_values', 'ARRAY<STRUCT<rank INT64, value STRING, count INT64, frequency FLOAT64>>')
    ])
), expected_schema as (
    select table_name, column_name, data_type from common_columns cross join unnest([
        '{{ all_profile.identifier }}', '{{ grouped_profile.identifier }}', '{{ empty_profile.identifier }}'
    ]) as table_name
    union all
    select '{{ grouped_profile.identifier }}', column_name, 'STRING'
    from unnest(['group_1_name', 'group_1_value', 'group_2_name', 'group_2_value']) as column_name
), actual_schema as (
    select table_name, column_name, data_type
    from `{{ all_profile.database }}.{{ all_profile.schema }}.INFORMATION_SCHEMA.COLUMNS`
    where table_name in ('{{ all_profile.identifier }}', '{{ grouped_profile.identifier }}', '{{ empty_profile.identifier }}')
), expected_types as (
    select * from unnest([
        struct('amount' as column_name, 'INT64' as column_type),
        struct('constant_numeric', 'NUMERIC'), struct('big_numeric', 'BIGNUMERIC'),
        struct('float_number', 'FLOAT64'), struct('label', 'STRING'), struct('flag', 'BOOL'),
        struct('calendar_date', 'DATE'), struct('local_datetime', 'DATETIME'),
        struct('happened_at', 'TIMESTAMP'), struct('local_time', 'TIME'), struct('byte_value', 'BYTES'),
        struct('json_value', 'JSON'), struct('geography_value', 'GEOGRAPHY')
    ])
), failures as (
    select concat(coalesce(e.table_name, a.table_name), '.', coalesce(e.column_name, a.column_name), ': output type/schema') as failure
    from expected_schema as e full outer join actual_schema as a using (table_name, column_name)
    where e.data_type is distinct from a.data_type
    union all
    select concat(p.column_name, ': source metadata')
    from {{ all_profile }} as p
    where source_relation is distinct from '{{ fixture.database }}.{{ fixture.schema }}.{{ fixture.identifier }}'
        or profiled_at is null or profiled_at > current_timestamp()
        or column_name is null or column_type is null
    union all
    select 'profiled_at: one execution timestamp'
    from (select count(distinct profiled_at) as timestamp_count from {{ all_profile }})
    where timestamp_count != 1
    union all
    select concat(e.column_name, ': canonical input type')
    from expected_types as e left join {{ all_profile }} as p using (column_name)
    where e.column_type is distinct from p.column_type
)
select * from failures
