{% materialization table_with_connector, adapter = "risingwave" %}
    {%- set identifier = model["alias"] -%}
    {%- set full_refresh_mode = should_full_refresh() -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database, type="table"
    ) -%}
    {%- set old_relation = risingwave__get_relation_without_caching(target_relation) -%}

    {% if full_refresh_mode and old_relation %} {{ adapter.drop_relation(old_relation) }} {% endif %}

    {{ run_hooks(pre_hooks, inside_transaction=False) }}
    {{ run_hooks(pre_hooks, inside_transaction=True) }}

    {% if old_relation is none or (full_refresh_mode and old_relation) %}
        {% call statement("main") -%} {{ risingwave__run_sql(sql) }} {%- endcall %}

        {{ create_indexes(target_relation) }}
    {% else %}
        {% set applied_table_schema_change = risingwave__handle_table_with_connector_on_schema_change(
            target_relation
        ) %}
        {{ risingwave__handle_on_configuration_change(old_relation, target_relation) }}
        {% if applied_table_schema_change %}
            {% do store_raw_result(name="main", message="ALTER_TABLE", code="ALTER_TABLE", rows_affected="-1") %}
        {% endif %}
    {% endif %}

    {% do persist_docs(target_relation, model) %}

    {{ run_hooks(post_hooks, inside_transaction=False) }}
    {{ run_hooks(post_hooks, inside_transaction=True) }}

    {{ return({"relations": [target_relation]}) }}
{% endmaterialization %}
