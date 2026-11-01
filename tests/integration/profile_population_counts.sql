{{ config(enabled=var('dbt_explore_integration_tests', false)) }}

with expected as (
    select country, count(*) as population_count
    from {{ ref('explore_population') }} where keep group by country
), profile as (select * from {{ ref('explore_profile_population') }}),
failures as (
    select concat(p.column_name, ': filtered/null-safe/missing population scope') as failure
    from profile as p left join expected as e
        on p.group_1_value is not distinct from e.country
    where p.population_count is distinct from e.population_count
        or p.group_1_name is distinct from 'country'
    union all
    select 'population: missing group remains null'
    from (select 1)
    where (select count(*) from profile where group_1_value = 'CA' and population_count is null) != 4
    union all
    select 'population: null keys match population null keys'
    from (select 1)
    where (select count(*) from profile where group_1_name = 'country' and group_1_value is null and population_count = 2) != 6
    union all
    select 'population: duplicate observations can exceed population'
    from (select 1)
    where not exists (select 1 from profile where group_1_value = 'ES' and group_2_value = 'web'
        and observation_count = 2 and population_count = 1)
    union all
    select 'population: independently filtered global denominator'
    from {{ ref('explore_profile_population_global') }}
    where population_count is distinct from 5
        or (group_1_value = 'ES' and observation_count is distinct from 3)
        or (group_1_value = 'US' and observation_count is distinct from 1)
        or group_1_value not in ('ES', 'US')
    union all
    select 'population: profile filter prevents eighth row'
    from (select 1)
    where (select sum(observation_count) from profile where column_name = 'amount' and group_2_name = 'channel') != 7
    union all
    select 'population: counts identical across profiled fields'
    from profile group by group_1_name, group_1_value, group_2_name, group_2_value
    having count(distinct population_count) > 1
)
select * from failures
