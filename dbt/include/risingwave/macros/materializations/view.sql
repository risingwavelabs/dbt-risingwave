{% materialization view, adapter='risingwave' %}
  {%- set identifier = model['alias'] -%}
  {%- set full_refresh_mode = should_full_refresh() -%}
  {%- set target_relation = api.Relation.create(identifier=identifier,
                                                schema=schema,
                                                database=database,
                                                type='view') -%}
  {%- set old_relation = risingwave__get_relation_without_caching(target_relation) -%}
  {%- set grant_config = config.get('grants') -%}

  {# Check both model config AND command line flag for zero downtime #}
  {%- set zero_downtime_config = config.get('zero_downtime', {}) -%}
  {%- set model_has_zero_downtime = zero_downtime_config.get('enabled', false) -%}
  {%- set user_requested_zero_downtime = var('zero_downtime', false) -%}
  {%- set zero_downtime_mode = model_has_zero_downtime and user_requested_zero_downtime -%}
  {%- set immediate_cleanup = zero_downtime_config.get('immediate_cleanup', false) -%}

  {{ risingwave__validate_model_sql(sql, 'view', true) }}

  {% if full_refresh_mode and old_relation %}
    {{ adapter.drop_relation(old_relation) }}
  {% endif %}

  {#- The model switched from another materialization: replace the old relation.
      Zero-downtime rebuilds keep their own swap-based path. -#}
  {% if not full_refresh_mode and not zero_downtime_mode %}
    {% set old_relation = risingwave__replace_relation_of_other_type(old_relation, target_relation) %}
  {% endif %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {{ risingwave__ensure_schema_authorization(target_relation) }}

  {% if old_relation is none %}
    {# First time creation #}
    {% call statement('main') -%}
      {{ risingwave__create_view_as(target_relation, sql) }}
    {%- endcall %}
  {% elif full_refresh_mode and old_relation %}
    {# Full refresh mode - already dropped above, create new #}
    {% call statement('main') -%}
      {{ risingwave__create_view_as(target_relation, sql) }}
    {%- endcall %}
  {% else %}
    {# View exists and not in full refresh mode #}
    {% if zero_downtime_mode %}
      {# Use zero downtime rebuild - both model config and user flag are enabled #}
      {{- log("Using zero downtime rebuild with SWAP for view update.") -}}
      
      {{ risingwave__check_zero_downtime_relation(old_relation, target_relation) }}

      {%- set temp_suffix = modules.datetime.datetime.now(modules.pytz.timezone('UTC')).isoformat().replace('-', '').replace(':', '').replace('.', '_') -%}
      {%- set temp_identifier = target_relation.identifier ~ "_dbt_zero_down_tmp_" ~ temp_suffix -%}
      {%- set temp_relation = api.Relation.create(
          identifier=temp_identifier,
          schema=target_relation.schema,
          database=target_relation.database,
          type='view'
      ) -%}

      {# Step 1: Create temporary view #}
      {% call statement('main') -%}
        {{ risingwave__create_view_with_temp_name(temp_relation, sql) }}
      {%- endcall %}

      {# Step 2: Grant on the new view before cut-over; privileges move with it through the swap #}
      {% do apply_grants(temp_relation, grant_config, should_revoke=false) %}

      {# Step 3: Cut over to the new view #}
      {%- set retired_relation = risingwave__zero_downtime_cut_over(old_relation, temp_relation, target_relation) -%}

      {# Step 4: Conditionally drop the old view (now with temp name) #}
      {% if immediate_cleanup %}
        {{- log("Attempting immediate cleanup of temporary " ~ retired_relation.type | replace('_', ' ') ~ ": " ~ retired_relation) -}}
        {{ risingwave__drop_zero_downtime_temp_relation(retired_relation) }}
      {% else %}
        {{- log("Preserving temporary " ~ retired_relation.type | replace('_', ' ') ~ " for downstream dependencies: " ~ retired_relation) -}}
        {{- log("Manual cleanup required: DROP " ~ retired_relation.type | replace('_', ' ') | upper ~ " IF EXISTS " ~ retired_relation ~ ";") -}}
      {% endif %}
    {% else %}
      {# Zero downtime disabled - either model config or user flag is missing #}
      {{- log("Zero downtime disabled for view (model config: " ~ model_has_zero_downtime ~ ", user flag: " ~ user_requested_zero_downtime ~ "). Using traditional handling.") -}}
      
      {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
    {% endif %}
  {% endif %}

  {% set should_revoke = should_revoke(existing_relation=old_relation, full_refresh_mode=full_refresh_mode) %}
  {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}

  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
