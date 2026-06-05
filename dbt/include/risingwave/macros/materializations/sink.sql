{% materialization sink, adapter = "risingwave" %}
    {%- set identifier = model["alias"] -%}
    {%- set full_refresh_mode = should_full_refresh() -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier,
        schema=schema,
        database=database,
        type="sink",
    ) -%}
    {%- set old_relation = risingwave__get_relation_without_caching(target_relation) -%}
    {%- set grant_config = config.get("grants") -%}

    {% if full_refresh_mode and old_relation %} {{ adapter.drop_relation(old_relation) }} {% endif %}

    {{ run_hooks(pre_hooks, inside_transaction=False) }}
    {{ run_hooks(pre_hooks, inside_transaction=True) }}

    {% if old_relation is none or (full_refresh_mode and old_relation) %}
        {%- set connector = config.get("connector") -%}
        {% call statement("main") -%}
            {% if connector %} {{ risingwave__create_sink(target_relation, sql) }}
            {% else %} {{ risingwave__run_sql(sql) }}
            {% endif %}
        {%- endcall %}
        {{ risingwave__wait_for_background_ddl(target_relation, "sink") }}
    {% else %} {{ risingwave__execute_no_op(target_relation) }}
    {% endif %}

    {% set should_revoke = should_revoke(existing_relation=old_relation, full_refresh_mode=full_refresh_mode) %}
    {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}

    {% do persist_docs(target_relation, model) %}

    {{ run_hooks(post_hooks, inside_transaction=False) }}
    {{ run_hooks(post_hooks, inside_transaction=True) }}

    {{ return({"relations": [target_relation]}) }}
{% endmaterialization %}
