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

  {# Check both model config AND command line flag for zero downtime #}
  {%- set zero_downtime_config = config.get('zero_downtime', {}) -%}
  {%- set model_has_zero_downtime = zero_downtime_config.get('enabled', false) -%}
  {%- set user_requested_zero_downtime = var('zero_downtime', false) -%}
  {%- set zero_downtime_mode = model_has_zero_downtime and user_requested_zero_downtime -%}
  {%- set immediate_cleanup = zero_downtime_config.get('immediate_cleanup', false) -%}

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
      {# Use zero downtime rebuild - both model config and user flag are enabled #}
      {{- log("Using zero downtime rebuild with SWAP for materialized view update.") -}}
      
      {%- set temp_suffix = modules.datetime.datetime.now(modules.pytz.timezone('UTC')).isoformat().replace('-', '').replace(':', '').replace('.', '_') -%}
      {%- set temp_identifier = target_relation.identifier ~ "_dbt_zero_down_tmp_" ~ temp_suffix -%}
      {%- set temp_relation = api.Relation.create(
          identifier=temp_identifier,
          schema=target_relation.schema,
          database=target_relation.database,
          type='materialized_view'
      ) -%}

      {# Step 1: Create temporary materialized view #}
      {% call statement('main') -%}
        {{ risingwave__create_materialized_view_with_temp_name(temp_relation, sql) }}
      {%- endcall %}

      {# Step 2: Swap the materialized views #}
      {% call statement('swap') -%}
        {{ risingwave__swap_materialized_views(old_relation, temp_relation) }}
      {%- endcall %}

      {# Step 3: Conditionally drop the old materialized view (now with temp name) #}
      {% if immediate_cleanup %}
        {{- log("Immediately cleaning up temporary materialized view: " ~ temp_relation) -}}
        {{ risingwave__drop_relation(temp_relation) }}
      {% else %}
        {{- log("Preserving temporary materialized view for downstream dependencies: " ~ temp_relation) -}}
        {{- log("Manual cleanup required: DROP MATERIALIZED VIEW IF EXISTS " ~ temp_relation ~ ";") -}}
      {% endif %}
      
      {{ create_indexes(target_relation) }}
    {% else %}
      {# Zero downtime disabled - either model config or user flag is missing #}
      {% if model_has_zero_downtime and not user_requested_zero_downtime %}
        {{- log("Model is configured for zero downtime, but --vars 'zero_downtime: true' was not provided. Using traditional rebuild.") -}}
      {% endif %}
      {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
    {% endif %}
  {% endif %}

  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
