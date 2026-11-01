{# Public interface: implementations belong to their adapter directories. #}
{% macro profile_relation(relation, columns=None, exclude_columns=None, where=None,
    group_by=None, grouping_sets=None, population=None, population_group_by=None,
    population_where=None, quantiles=4, extra_percentiles=None, top_n=10) %}
  {{ return(adapter.dispatch('profile_relation', 'dbt_explore')(
      relation=relation, columns=columns, exclude_columns=exclude_columns, where=where,
      group_by=group_by, grouping_sets=grouping_sets, population=population,
      population_group_by=population_group_by, population_where=population_where,
      quantiles=quantiles, extra_percentiles=extra_percentiles, top_n=top_n)) }}
{% endmacro %}

{% macro default__profile_relation(relation, columns=None, exclude_columns=None, where=None,
    group_by=None, grouping_sets=None, population=None, population_group_by=None,
    population_where=None, quantiles=4, extra_percentiles=None, top_n=10) %}
  {% if execute %}
    {{ exceptions.raise_compiler_error("dbt_explore: profile_relation not implemented for adapter '" ~ target.type ~ "'. Supported: bigquery.") }}
  {% endif %}
  {{ return('') }}
{% endmacro %}
