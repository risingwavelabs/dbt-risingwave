{% materialization materialized_view, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set old_relation = adapter.get_relation(identifier=identifier,
                                              schema=schema,
                                              database=database) -%}
  {%- set target_relation = api.Relation.create(identifier=identifier,
                                                schema=schema,
                                                database=database,
                                                type='materialized_view') -%}

  {%- set zero_downtime_mode = config.get('zero_downtime', true) -%}

  {% if full_refresh_mode and old_relation %}
    {{ adapter.drop_relation(old_relation) }}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if old_relation is none %}
    {# First time creation #}
    {% call statement('main') -%}
      {{ risingwave__create_materialized_view_as(target_relation, sql) }}
    {%- endcall %}

    {{ create_indexes(target_relation) }}
  {% elif full_refresh_mode and old_relation %}
    {# Full refresh mode - already dropped above, create new #}
    {% call statement('main') -%}
      {{ risingwave__create_materialized_view_as(target_relation, sql) }}
    {%- endcall %}

    {{ create_indexes(target_relation) }}
  {% else %}
    {# MV exists and not in full refresh mode #}
    {%- set configuration_changes = get_materialized_view_configuration_changes(old_relation, config) -%}
    
    {% if configuration_changes is not none and zero_downtime_mode %}
      {# There are SQL changes, use zero downtime rebuild #}
      {{- log("Detected changes to materialized view definition. Using zero downtime rebuild with SWAP.") -}}
      {% call statement('main') -%}
        {{ risingwave__zero_downtime_materialized_view_rebuild(old_relation, target_relation, sql) }}
      {%- endcall %}
      
      {{ create_indexes(target_relation) }}
    {% else %}
      {# No changes or zero_downtime disabled, use existing configuration change handling #}
      {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
    {% endif %}
  {% endif %}

  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
