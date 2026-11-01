{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

select * from {{ ref('explore_fixture') }} where false
