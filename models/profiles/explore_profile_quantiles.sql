{{ config(materialized='table', enabled=var('dbt_explore_integration_tests', false)) }}

{% for scenario, intervals, extras in [
    ('thirds', 3, [0, 50, 95, 95, 100]),
    ('deciles', 10, none),
    ('extras_only', 0, [95, 50, 95])
] %}
select '{{ scenario }}' as scenario, profile.*
from (
    {{ dbt_explore.profile_relation(
        relation=ref('explore_fixture'),
        columns=['amount', 'constant_numeric', 'null_number'],
        quantiles=intervals,
        extra_percentiles=extras
    ) }}
) as profile
{% if not loop.last %}union all{% endif %}
{% endfor %}
