{% macro test_invalid_profile_arguments(case) %}
    {% set fixture = ref('explore_fixture') %}
    {% set args = {'relation': fixture, 'columns': ['amount']} %}
    {% if case == 'relation_sql' %}
        {% do args.update({'relation': 'select 1 as amount'}) %}
    {% elif case == 'relation_mapping' %}
        {% do args.update({'relation': {'database': fixture.database, 'schema': fixture.schema, 'identifier': fixture.identifier, 'type': 'table'}}) %}
    {% elif case == 'relation_ephemeral' %}
        {% do args.update({'relation': api.Relation.create(database=fixture.database, schema=fixture.schema, identifier='ephemeral_fixture', type='cte')}) %}
    {% elif case == 'columns_string' %}
        {% do args.update({'columns': 'amount'}) %}
    {% elif case == 'columns_empty' %}
        {% do args.update({'columns': []}) %}
    {% elif case == 'columns_unknown' %}
        {% do args.update({'columns': ['does_not_exist']}) %}
    {% elif case == 'exclude_unknown' %}
        {% do args.update({'exclude_columns': ['does_not_exist']}) %}
    {% elif case == 'exclude_all' %}
        {% do args.update({'exclude_columns': ['amount']}) %}
    {% elif case == 'where_not_sql' %}
        {% do args.update({'where': 42}) %}
    {% elif case == 'groups_mutually_exclusive' %}
        {% do args.update({'group_by': [], 'grouping_sets': [[]]}) %}
    {% elif case == 'groups_unknown' %}
        {% do args.update({'group_by': ['does_not_exist']}) %}
    {% elif case == 'groups_parent' %}
        {% do args.update({'group_by': ['customer']}) %}
    {% elif case == 'groups_array' %}
        {% do args.update({'group_by': ['items']}) %}
    {% elif case == 'groups_json' %}
        {% do args.update({'group_by': ['json_value']}) %}
    {% elif case == 'groups_duplicate_dimension' %}
        {% do args.update({'group_by': ['country', 'country']}) %}
    {% elif case == 'groups_empty_sets' %}
        {% do args.update({'grouping_sets': []}) %}
    {% elif case == 'groups_string_set' %}
        {% do args.update({'grouping_sets': ['country']}) %}
    {% elif case == 'groups_null_set' %}
        {% do args.update({'grouping_sets': [none]}) %}
    {% elif case == 'groups_duplicate_sets' %}
        {% do args.update({'grouping_sets': [['country'], ['country']]}) %}
    {% elif case == 'quantiles_negative' %}
        {% do args.update({'quantiles': -1}) %}
    {% elif case == 'quantiles_fraction' %}
        {% do args.update({'quantiles': 1.5}) %}
    {% elif case == 'quantiles_boolean' %}
        {% do args.update({'quantiles': true}) %}
    {% elif case == 'quantiles_string' %}
        {% do args.update({'quantiles': '4'}) %}
    {% elif case == 'percentiles_range' %}
        {% do args.update({'extra_percentiles': [101]}) %}
    {% elif case == 'percentiles_fraction' %}
        {% do args.update({'extra_percentiles': [95.5]}) %}
    {% elif case == 'percentiles_boolean' %}
        {% do args.update({'extra_percentiles': [true]}) %}
    {% elif case == 'top_negative' %}
        {% do args.update({'top_n': -1}) %}
    {% elif case == 'top_fraction' %}
        {% do args.update({'top_n': 1.5}) %}
    {% elif case == 'top_boolean' %}
        {% do args.update({'top_n': true}) %}
    {% elif case == 'population_missing' %}
        {% do args.update({'population_group_by': []}) %}
    {% elif case == 'population_where_missing' %}
        {% do args.update({'population_where': 'keep'}) %}
    {% elif case == 'population_not_subset' %}
        {% do args.update({'group_by': ['channel'], 'population': ref('explore_population'), 'population_group_by': ['country']}) %}
    {% elif case == 'population_incompatible_sets' %}
        {% do args.update({'grouping_sets': [[], ['country']], 'population': ref('explore_population'), 'population_group_by': ['country']}) %}
    {% elif case == 'population_incompatible_types' %}
        {% do args.update({'group_by': ['country'], 'population': ref('explore_population_incompatible'), 'population_group_by': ['country']}) %}
    {% else %}
        {{ exceptions.raise_compiler_error('Unknown invalid-argument test case: ' ~ case) }}
    {% endif %}
    {% do dbt_explore.profile_relation(**args) %}
    {{ exceptions.raise_compiler_error('Invalid argument unexpectedly accepted: ' ~ case) }}
{% endmacro %}
