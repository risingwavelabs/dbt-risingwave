{% materialization connection, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set target_relation = api.Relation.create(
      identifier=identifier,
      schema=schema,
      database=database,
      type='connection'
  ) -%}
  {%- set existing_connection = false -%}

  {% if execute %}
    {% set connection_exists_sql %}
      select 1
      from rw_catalog.rw_connections c
      where c.name = '{{ identifier }}'
      limit 1
    {% endset %}
    {% set existing_connection_result = run_query(connection_exists_sql) %}
    {% if existing_connection_result is not none and (existing_connection_result.rows | length) > 0 %}
      {%- set existing_connection = true -%}
    {% endif %}
  {% endif %}

  {% if full_refresh_mode and existing_connection %}
    {% call statement('drop_connection') -%}
      drop connection if exists "{{ identifier }}"
    {%- endcall %}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if not existing_connection or (full_refresh_mode and existing_connection) %}
    {% call statement('main') -%}
      {{ risingwave__run_sql(sql) }}
    {%- endcall %}
  {% else %}
    {{ risingwave__execute_no_op(target_relation) }}
  {% endif %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
