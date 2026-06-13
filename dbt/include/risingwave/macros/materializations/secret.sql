{% materialization secret, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set target_relation = api.Relation.create(
      identifier=identifier,
      schema=schema,
      database=database,
      type='secret'
  ) -%}
  {%- set existing_secret = false -%}
  {%- set old_relation = none -%}
  {%- set grant_config = config.get("grants") -%}

  {% if execute %}
    {% set secret_exists_sql %}
      select 1
      from rw_catalog.rw_secrets s
      join rw_catalog.rw_schemas sc on s.schema_id = sc.id
      where sc.name = '{{ schema }}'
        and s.name = '{{ identifier }}'
      limit 1
    {% endset %}
    {% set existing_secret_result = run_query(secret_exists_sql) %}
    {% if existing_secret_result is not none and (existing_secret_result.rows | length) > 0 %}
      {%- set existing_secret = true -%}
      {%- set old_relation = target_relation -%}
    {% endif %}
  {% endif %}

  {% if full_refresh_mode and existing_secret %}
    {% call statement('drop_secret') -%}
      drop secret if exists {{ target_relation }} cascade
    {%- endcall %}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if not existing_secret or (full_refresh_mode and existing_secret) %}
    {% call statement('main') -%}
      {{ risingwave__run_sql(sql) }}
    {%- endcall %}
  {% else %}
    {{ risingwave__execute_no_op(target_relation) }}
  {% endif %}

  {% set should_revoke = should_revoke(existing_relation=old_relation, full_refresh_mode=full_refresh_mode) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
