{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with expected_groups as (
    select country, channel, count(*) as observation_count
    from {{ ref('explore_fixture') }} group by country, channel
), grouped as (select * from {{ ref('explore_profile_grouped') }}),
sets as (select * from {{ ref('explore_profile_sets') }}),
failures as (
    select 'grouped: expected three columns in each observed group' as failure
    from (select 1)
    where (select count(*) from grouped) != 3 * (select count(*) from expected_groups)
    union all
    select concat(p.column_name, ': group count or caller pair order')
    from grouped as p
    left join expected_groups as e
        on p.group_1_value is not distinct from e.country
        and p.group_2_value is not distinct from e.channel
    where p.observation_count is distinct from e.observation_count
        or p.group_1_name is distinct from 'country' or p.group_2_name is distinct from 'channel'
        or p.grouping_level is distinct from 'country,channel'
        or json_value(p.grouping_flags, '$.country') is distinct from '0'
        or json_value(p.grouping_flags, '$.channel') is distinct from '0'
    union all
    select 'grouped: explicitly selected dimension must be profiled'
    from (select 1)
    where (select count(*) from grouped where column_name = 'country') != (select count(*) from expected_groups)
    union all
    select concat(column_name, ': grouping sets pair order and flags')
    from sets
    where
        -- The first occurrence of channel precedes country across the sets.
        (json_value(grouping_flags, '$.channel') = '0' and group_1_name is distinct from 'channel')
        or (json_value(grouping_flags, '$.country') = '0' and group_2_name is distinct from 'country')
        or (json_value(grouping_flags, '$.channel') = '1' and (group_1_name is not null or group_1_value is not null))
        or (json_value(grouping_flags, '$.country') = '1' and (group_2_name is not null or group_2_value is not null))
        or (grouping_level is null and (observation_count != 8
            or json_value(grouping_flags, '$.country') is distinct from '1'
            or json_value(grouping_flags, '$.channel') is distinct from '1'))
        or (group_1_name = 'channel' and group_2_name = 'country' and grouping_level is distinct from 'channel,country')
    union all
    select 'grouping sets: aggregate cardinality'
    from (select 1)
    where (select count(*) from sets) != 2 * (
        1 + (select count(distinct channel) + countif(channel is null) from (select distinct channel from {{ ref('explore_fixture') }}))
        + (select count(*) from expected_groups)
    )
    union all
    select 'grouping sets: preserve actual null grouping keys'
    from (select 1)
    where (select count(*) from sets
        where group_1_name = 'channel' and group_1_value is null
        and group_2_name = 'country' and group_2_value is null
        and json_value(grouping_flags, '$.country') = '0'
        and json_value(grouping_flags, '$.channel') = '0') != 2
    union all
    select 'typed grouping: native aggregation and final string serialization'
    from {{ ref('explore_profile_typed_groups') }} as p
    left join (
        select byte_value, amount, flag, count(*) as observation_count
        from {{ ref('explore_fixture') }} group by byte_value, amount, flag
    ) as e
        on p.group_1_value is not distinct from to_base64(e.byte_value)
        and p.group_2_value is not distinct from cast(e.amount as string)
        and p.group_3_value is not distinct from cast(e.flag as string)
    where p.observation_count is distinct from e.observation_count
        or p.group_1_name is distinct from 'byte_value'
        or p.group_2_name is distinct from 'amount'
        or p.group_3_name is distinct from 'flag'
)
select * from failures
