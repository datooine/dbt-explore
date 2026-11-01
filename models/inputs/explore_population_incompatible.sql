{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

-- Same dimension name with an incompatible physical type for validation tests.
select 1 as country, true as keep
