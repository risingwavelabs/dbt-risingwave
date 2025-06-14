{% materialization materializedview, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set old_relation = adapter.get_relation(identifier=identifier,
                                              schema=schema,
                                              database=database) -%}
  {%- set target_relation = api.Relation.create(identifier=identifier,
                                                schema=schema,
                                                database=database,
                                                type='materializedview') -%}

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
    {% if zero_downtime_mode %}
      {# Use zero downtime rebuild #}
      {{- log("Using zero downtime rebuild with SWAP for materialized view update.") -}}
      
      {%- set temp_suffix = modules.datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f") -%}
      {%- set temp_identifier = target_relation.identifier ~ "_tmp_" ~ temp_suffix -%}
      {%- set temp_relation = api.Relation.create(
          identifier=temp_identifier,
          schema=target_relation.schema,
          database=target_relation.database,
          type='materialized_view'
      ) -%}

      {# Step 1: Create temporary materialized view #}
      {% call statement('create_temp_mv') -%}
        {{ risingwave__create_materialized_view_with_temp_name(temp_relation, sql) }}
      {%- endcall %}

      {# Step 2: Swap the materialized views - This is the main operation #}
      {% call statement('main') -%}
        {{ risingwave__swap_materialized_views(old_relation, temp_relation) }}
      {%- endcall %}

      {# Step 3: Drop the old materialized view (now with temp name) #}
      {% call statement('drop_old_mv') -%}
        drop materialized view if exists {{ temp_relation }} cascade
      {%- endcall %}
      
      {{ create_indexes(target_relation) }}
    {% else %}
      {# Zero downtime disabled, use existing configuration change handling #}
      {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
    {% endif %}
  {% endif %}

  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
