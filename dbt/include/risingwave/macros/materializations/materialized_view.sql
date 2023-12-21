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

<<<<<<< HEAD
  {% if full_refresh_mode and old_relation %}
    {{ adapter.drop_relation(old_relation) }}
  {% endif %}
=======
  {%- set tmp_relation = api.Relation.create(identifier=identifier,
                                                schema="tmp",
                                                database=database,
                                                type='materializedview') -%}

>>>>>>> d8b8942 (zero downtime MV)

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

<<<<<<< HEAD
  {% if old_relation is none or (full_refresh_mode and old_relation) %}
    {% call statement('main') -%}
      {{ risingwave__create_materialized_view_as(target_relation, sql) }}
    {%- endcall %}

    {{ create_indexes(target_relation) }}
  {% else %}
    -- get config options
    {% set on_configuration_change = config.get('on_configuration_change') %}
    {% set configuration_changes = get_materialized_view_configuration_changes(old_relation, config) %}

    {% if configuration_changes is none %}
      -- do nothing
      {{ materialized_view_execute_no_op(target_relation) }}
    {% elif on_configuration_change == 'apply' %}
      {% call statement('main') -%}
        {{ risingwave__update_indexes_on_materialized_view(target_relation, configuration_changes.indexes) }}
      {%- endcall %}
    {% elif on_configuration_change == 'continue' %}
        -- do nothing but a warn
        {{ exceptions.warn("Configuration changes were identified and `on_configuration_change` was set to `continue` for `" ~ target_relation ~ "`") }}
        {{ materialized_view_execute_no_op(target_relation) }}
    {% elif on_configuration_change == 'fail' %}
        {{ exceptions.raise_fail_fast_error("Configuration changes were identified and `on_configuration_change` was set to `fail` for `" ~ target_relation ~ "`") }}
    {% else %}
        -- this only happens if the user provides a value other than `apply`, 'continue', 'fail'
        {{ exceptions.raise_compiler_error("Unexpected configuration scenario") }}

    {% endif %}
  {% endif %}

=======
  {{ adapter.drop_relation(tmp_relation) }}

  {% call statement('main') -%}
    {{ risingwave__create_materialized_view_as(tmp_relation, sql) }}
  {%- endcall %}

  {% if old_relation %}
    {{ adapter.drop_relation(old_relation) }}
  {% endif %}

  {% set query %}
      ALTER MATERIALIZED VIEW  {{ tmp_relation }} SET SCHEMA {{ target_relation.schema }}
  {% endset %}
  {% do run_query(query) %}

  {{ create_indexes(target_relation) }}
>>>>>>> d8b8942 (zero downtime MV)
  {% do persist_docs(target_relation, model) %}

  {{ run_hooks(post_hooks, inside_transaction=False) }}
  {{ run_hooks(post_hooks, inside_transaction=True) }}

  {{ return({'relations': [target_relation]}) }}
{% endmaterialization %}
