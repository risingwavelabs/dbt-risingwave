{%- materialization test, adapter='risingwave' -%}

  {% set relations = [] %}

  {% if should_store_failures() %}

    {% set identifier = model['alias'] %}
    {% set old_relation = adapter.get_relation(database=database, schema=schema, identifier=identifier) %}

    {% set store_failures_as = config.get('store_failures_as') %}
    {% if store_failures_as == none %}{% set store_failures_as = 'table' %}{% endif %}
    {% if store_failures_as not in ['table', 'view', 'materialized_view'] %}
        {{ exceptions.raise_compiler_error(
            "'" ~ store_failures_as ~ "' is not a valid value for `store_failures_as`. "
            "Accepted values are: ['ephemeral', 'table', 'view', 'materialized_view']"
        ) }}
    {% endif %}

    {% set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database, type=store_failures_as) -%} %}

    {% if old_relation %}
        {% do adapter.drop_relation(old_relation) %}
    {% endif %}

    {% if store_failures_as == 'view' %}
        {% call statement(auto_begin=True) %}
            {{ risingwave__create_view_as(target_relation, sql) }}
        {% endcall %}
    {% elif store_failures_as == 'materialized_view' %}
        {% call statement(auto_begin=True) %}
            {{ risingwave__create_materialized_view_as(target_relation, sql) }}
        {% endcall %}
    {% else %}
        {% call statement(auto_begin=True) %}
            {{ risingwave__create_table_as(False, target_relation, sql) }}
        {% endcall %}
    {% endif %}

    {% do relations.append(target_relation) %}

    {% set main_sql %}
        select *
        from {{ target_relation }}
    {% endset %}

    {{ adapter.commit() }}

  {% else %}

      {% set main_sql = sql %}

  {% endif %}

  {% set limit = config.get('limit') %}
  {% set fail_calc = config.get('fail_calc') %}
  {% set warn_if = config.get('warn_if') %}
  {% set error_if = config.get('error_if') %}

  {% call statement('main', fetch_result=True) -%}

    {{ get_test_sql(main_sql, fail_calc, warn_if, error_if, limit)}}

  {%- endcall %}

  {{ return({'relations': relations}) }}

{%- endmaterialization -%}
