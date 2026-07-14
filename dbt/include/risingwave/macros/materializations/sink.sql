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
    {%- set connector = config.get("connector") -%}
    {%- set zero_downtime_config = config.get("zero_downtime", {}) -%}
    {%- set model_has_zero_downtime = zero_downtime_config.get("enabled", false) -%}
    {%- set user_requested_zero_downtime = var("zero_downtime", false) -%}
    {%- set zero_downtime_mode = model_has_zero_downtime and user_requested_zero_downtime -%}
    {%- set replace_mode = old_relation is not none and not full_refresh_mode and zero_downtime_mode -%}
    {%- set replace_from_relation = none -%}

    {% if replace_mode %}
        {%- set replace_from_relation = risingwave__replace_sink_from_relation(sql, connector) -%}
    {% endif %}

    {{ risingwave__validate_model_sql(sql, "sink", connector is not none) }}

    {% if full_refresh_mode and old_relation %}
        {% if zero_downtime_mode %}
            {{- log("Zero downtime sink replacement is disabled under --full-refresh because REPLACE SINK does not backfill. Using drop/create.") -}}
        {% endif %}
        {{ adapter.drop_relation(old_relation) }}
    {% endif %}

    {{ run_hooks(pre_hooks, inside_transaction=False) }}
    {{ run_hooks(pre_hooks, inside_transaction=True) }}

    {% if old_relation is none or (full_refresh_mode and old_relation) %}
        {% call statement("main") -%}
            {% if connector %} {{ risingwave__create_sink(target_relation, sql) }}
            {% else %} {{ risingwave__run_sql(sql) }}
            {% endif %}
        {%- endcall %}
        {{ risingwave__wait_for_background_ddl(target_relation, "sink") }}
    {% elif replace_mode %}
        {{- log("Using REPLACE SINK for zero downtime sink cut-over.") -}}
        {% call statement("main") -%}
            {{ risingwave__replace_sink(target_relation, replace_from_relation) }}
        {%- endcall %}
        {{ risingwave__wait_for_replace_sink() }}
    {% else %} {{ risingwave__execute_no_op(target_relation) }}
    {% endif %}

    {%- set relation_recreated = full_refresh_mode or replace_mode -%}
    {% set should_revoke = should_revoke(existing_relation=old_relation, full_refresh_mode=relation_recreated) %}
    {% do apply_grants(target_relation, grant_config, should_revoke=should_revoke) %}

    {% do persist_docs(target_relation, model) %}

    {{ run_hooks(post_hooks, inside_transaction=False) }}
    {{ run_hooks(post_hooks, inside_transaction=True) }}

    {{ return({"relations": [target_relation]}) }}
{% endmaterialization %}
