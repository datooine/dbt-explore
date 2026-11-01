{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- if node is not none and node.package_name == 'dbt_explore'
        and node.resource_type == 'model'
        and (node.path.startswith('inputs/') or node.path.startswith('profiles/')) -%}
        {{ var('dbt_explore_test_prefix', env_var('DBT_EXPLORE_TEST_PREFIX', 'dbt_explore_')) }}{{ node.name }}
    {%- elif custom_alias_name is not none -%}
        {{ custom_alias_name | trim }}
    {%- else -%}
        {{ node.name }}
    {%- endif -%}
{%- endmacro %}
