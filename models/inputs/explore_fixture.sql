{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

-- Persisted fixtures intentionally contain no null array elements: BigQuery
-- rejects those when a query result is stored. The view fixture covers them.
select
    id,
    case when id <= 3 then 'ES' when id = 4 then 'US' when id >= 7 then 'CA' end as country,
    case when id in (1, 2, 4) then 'web' when id in (3, 5, 7, 8) then 'app' end as channel,
    case id when 1 then 0 when 2 then 10 when 3 then -10 when 4 then 20 end as amount,
    cast(7.5 as numeric) as constant_numeric,
    if(id <= 4, cast(1.5 as bignumeric), null) as big_numeric,
    if(id <= 4, cast(id as float64) / 2, null) as float_number,
    cast(null as int64) as null_number,
    case id when 1 then 'alpha' when 2 then 'alpha' when 3 then 'beta' when 4 then '' end as label,
    cast(null as string) as null_string,
    case when id in (1, 3) then true when id = 2 then false end as flag,
    case id when 1 then date '2026-01-03' when 2 then date '2026-01-01' end as calendar_date,
    case id when 1 then datetime '2026-01-03 12:00:00' when 2 then datetime '2026-01-01 01:02:03' end as local_datetime,
    case id when 1 then timestamp '2026-01-03 12:00:00+00' when 2 then timestamp '2026-01-01 01:02:03+00' end as happened_at,
    case id when 1 then time '12:00:00' when 2 then time '01:02:03' end as local_time,
    case id when 1 then b'ab' when 2 then b'' when 3 then b'c' end as byte_value,
    if(id <= 2, parse_json('{"ok":true}'), null) as json_value,
    if(id <= 2, st_geogpoint(1, 2), null) as geography_value,
    if(
        id = 4,
        cast(null as struct<id string, address struct<country string, city string>>),
        struct(
            if(id <= 2, concat('c', cast(id as string)), null) as id,
            struct(
                if(id <= 3, 'ES', null) as country,
                case id when 1 then 'Madrid' when 2 then 'Seville' end as city
            ) as address
        )
    ) as customer,
    case id when 1 then [1, 2] when 3 then [3] when 7 then [4, 5, 6] else array<int64>[] end as items,
    if(id <= 2, [struct('sku' as sku, id as quantity)], array<struct<sku string, quantity int64>>[]) as records
from unnest(generate_array(1, 8)) as id
