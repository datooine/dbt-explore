{{ config(materialized='view', enabled=var('dbt_explore_integration_tests', false)) }}

select
    *,
    case
        when id = 1 then cast(null as array<int64>)
        when id = 2 then array<int64>[]
        when id = 3 then [cast(null as int64), 1]
        else [1]
    end as transient_items
from {{ ref('explore_fixture') }}
