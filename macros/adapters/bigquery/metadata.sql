{# Adapter metadata is normalized through data_type, available on Core and v2.
   Do not use Column.flatten(): it descends into repeated RECORDs on Core. #}
{% macro _bq_profile_error(message) %}
  {{ exceptions.raise_compiler_error('dbt_explore.profile_relation: ' ~ message) }}
{% endmacro %}

{% macro _bq_profile_literal(value) %}
  {{ return("'" ~ (value | string | replace('\\', '\\\\') | replace("'", "\\'")) ~ "'") }}
{% endmacro %}

{% macro _bq_profile_path(parts) %}
  {% set quoted = [] %}
  {% for part in parts %}
    {% do quoted.append('`' ~ (part | replace('\\', '\\\\') | replace('`', '\\`')) ~ '`') %}
  {% endfor %}
  {{ return(quoted | join('.')) }}
{% endmacro %}

{% macro _bq_profile_fields(name, data_type, prefix=[]) %}
  {% set dtype = data_type | trim %}
  {% set parts = prefix + [name] %}
  {% set family = dtype.split('<')[0].split('(')[0] | trim | upper %}
  {% set aliases = {'INTEGER':'INT64', 'INT':'INT64', 'SMALLINT':'INT64', 'BIGINT':'INT64',
      'FLOAT':'FLOAT64', 'BOOLEAN':'BOOL', 'DECIMAL':'NUMERIC', 'BIGDECIMAL':'BIGNUMERIC', 'RECORD':'STRUCT'} %}
  {% set family = aliases.get(family, family) %}
  {% if family == 'STRUCT' %}
    {% set children = [] %}
    {% set ns = namespace(depth=0, quoted=false, escaped=false, current='') %}
    {% for char in dtype[dtype.find('<') + 1:-1] %}
      {% if char == ',' and ns.depth == 0 and not ns.quoted %}
        {% do children.append(ns.current | trim) %}
        {% set ns.current = '' %}
      {% else %}
        {% set ns.current = ns.current ~ char %}
        {% if char == '`' and not ns.escaped %}{% set ns.quoted = not ns.quoted %}{% endif %}
        {% if not ns.quoted %}
          {% if char == '<' or char == '(' %}{% set ns.depth = ns.depth + 1 %}{% endif %}
          {% if char == '>' or char == ')' %}{% set ns.depth = ns.depth - 1 %}{% endif %}
        {% endif %}
        {% set ns.escaped = char == '\\' and not ns.escaped %}
      {% endif %}
    {% endfor %}
    {% if ns.current | trim %}{% do children.append(ns.current | trim) %}{% endif %}
    {% set leaves = [] %}
    {% for child in children %}
      {% set match = modules.re.match('^(`(?:\\\\.|[^`])*`|[^\\s]+)\\s+(.+)$', child) %}
      {% if match is none %}{{ dbt_explore._bq_profile_error('Cannot interpret STRUCT metadata for ' ~ (parts | join('.')) ~ ': ' ~ child) }}{% endif %}
      {% set child_name = match.group(1) %}
      {% if child_name.startswith('`') %}{% set child_name = child_name[1:-1] | replace('\\`', '`') | replace('\\\\', '\\') %}{% endif %}
      {% do leaves.extend(dbt_explore._bq_profile_fields(child_name, match.group(2), parts)) %}
    {% endfor %}
    {{ return(leaves) }}
  {% endif %}
  {% set normalized_type = dtype if family == 'ARRAY' else family %}
  {{ return([{'name': parts | join('.'), 'parts': parts, 'type': normalized_type,
      'family': family, 'sql': dbt_explore._bq_profile_path(parts)}]) }}
{% endmacro %}

{% macro _bq_profile_discover(relation, argument='relation') %}
  {# Core's Relation implements Mapping itself; require its SQL renderer instead
     of rejecting every mapping (which would reject valid ref() values). #}
  {% if relation is none or relation is string or relation.render is not defined or relation.database is not defined or relation.schema is not defined or relation.identifier is not defined %}
    {{ dbt_explore._bq_profile_error(argument ~ ' must be a physical dbt Relation (table or view), not a SQL string or CTE.') }}
  {% endif %}
  {% if (relation.is_cte is defined and relation.is_cte) or (relation.type is defined and relation.type | string | lower in ['cte', 'c_t_e', 'ephemeral']) %}
    {{ dbt_explore._bq_profile_error(argument ~ ' must be a physical table or view; ephemeral models are not supported.') }}
  {% endif %}
  {% set physical = adapter.get_relation(database=relation.database, schema=relation.schema, identifier=relation.identifier) %}
  {% if physical is none %}{{ dbt_explore._bq_profile_error(argument ~ ' does not exist: ' ~ relation ~ '. Materialize upstream models before compiling profiles.') }}{% endif %}
  {% if physical.type | string | lower not in ['table', 'view', 'external', 'materialized_view'] %}
    {{ dbt_explore._bq_profile_error(argument ~ ' must be a physical table or view.') }}
  {% endif %}
  {% set fields = [] %}
  {% for column in adapter.get_columns_in_relation(physical) %}
    {% do fields.extend(dbt_explore._bq_profile_fields(column.name, column.data_type)) %}
  {% endfor %}
  {% if not fields %}{{ dbt_explore._bq_profile_error('No fields discovered in ' ~ argument ~ ': ' ~ relation) }}{% endif %}
  {{ return(fields) }}
{% endmacro %}

{% macro _bq_profile_list(value, argument) %}
  {% if value is none %}{{ return([]) }}{% endif %}
  {% if value is string or value is mapping or value is not sequence %}
    {{ dbt_explore._bq_profile_error(argument ~ ' must be a list of non-empty field paths.') }}
  {% endif %}
  {% for item in value %}
    {% if item is not string or not item | trim %}{{ dbt_explore._bq_profile_error(argument ~ ' must contain only non-empty field paths.') }}{% endif %}
  {% endfor %}
  {{ return(value) }}
{% endmacro %}

{% macro _bq_profile_resolve(paths, fields, argument, parents=false) %}
  {% set resolved = [] %}
  {% set seen = [] %}
  {% for path in paths %}
    {% set ns = namespace(found=false) %}
    {% for field in fields %}
      {% if field.name | lower == path | lower or (parents and (field.name | lower).startswith((path | lower) ~ '.')) %}
        {% set ns.found = true %}
        {% if field.name not in seen %}
          {% do resolved.append(field) %}{% do seen.append(field.name) %}
        {% endif %}
      {% endif %}
    {% endfor %}
    {% if not ns.found %}{{ dbt_explore._bq_profile_error(argument ~ ' contains an unknown or unsupported path: ' ~ path) }}{% endif %}
  {% endfor %}
  {{ return(resolved) }}
{% endmacro %}

{% macro _bq_profile_string(expression, family) %}
  {{ return(('TO_BASE64(' if family == 'BYTES' else 'CAST(') ~ expression ~ (')' if family == 'BYTES' else ' AS STRING)')) }}
{% endmacro %}
