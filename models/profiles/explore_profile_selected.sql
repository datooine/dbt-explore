{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{{ dbt_explore.profile_relation(
    relation=ref('explore_fixture'),
    columns=['customer', 'amount', 'label', 'items'],
    exclude_columns=['customer.address.city', 'items'],
    group_by=['customer.address.country'],
    where='id <= 4'
) }}
