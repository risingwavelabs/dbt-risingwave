-- The original postgres adapter only queries tables and views without index.
-- But materialize verison includes 'index' type.
-- Here we only query table, view, materialized view and source. (without index and SINK)
{% macro risingwave__list_relations_without_caching(schema_relation) %}
  {% call statement('list_relations_without_caching', fetch_result=True) -%}
    select
    '{{ schema_relation.database }}' as database,
    rw_relations.name as name,
    rw_schemas.name as schema,
    CASE WHEN relation_type = 'materialized view' THEN
      'materialized_view'
      else relation_type
    END AS type
    from rw_relations join rw_schemas on schema_id=rw_schemas.id
    where rw_schemas.name not in ('rw_catalog', 'information_schema', 'pg_catalog')
    and relation_type in ('table', 'view', 'source', 'sink', 'materialized view', 'index')
    AND rw_schemas.name = '{{ schema_relation.schema }}'
  {% endcall %}
  {{ return(load_result('list_relations_without_caching').table) }}
{% endmacro %}

{% macro risingwave__get_columns_in_relation(relation) -%}
  {% call statement('get_columns_in_relation', fetch_result=True) %}
      select
          column_name,
          data_type,
          null as character_maximum_length,
          null as numeric_precision,
          null as numeric_scale

      from {{ relation.information_schema('columns') }}
      where table_name = '{{ relation.identifier }}'
        {% if relation.schema %}
        and table_schema = '{{ relation.schema }}'
        {% endif %}
      order by ordinal_position

  {% endcall %}
  {% set table = load_result('get_columns_in_relation').table %}
  {{ return(sql_convert_columns_in_relation(table)) }}
{% endmacro %}


{% macro risingwave__get_create_index_sql(relation, index_dict) -%}
  {%- set index_config = adapter.parse_index(index_dict) -%}
  {%- set comma_separated_columns = ", ".join(index_config.columns) -%}
  {%- set index_name = "__dbt_index_" + relation.identifier + "_" + "_".join(index_config.columns) -%}

  create index if not exists
  "{{ index_name }}"
  on {{ relation }}
  ({{ comma_separated_columns }});
{%- endmacro %}

{%- macro risingwave__get_drop_index_sql(relation, index_name) -%}
    drop index if exists "{{ relation.schema }}"."{{ index_name }}"
{%- endmacro -%}

{% macro risingwave__drop_relation(relation) -%}
  {% call statement('drop_relation') -%}
    {% if relation.type == 'view' %}
      drop view if exists {{ relation }} cascade
    {% elif relation.type == 'table' %}
      drop table if exists {{ relation }} cascade
    {% elif relation.type == 'materializedview' %}
      drop materialized view if exists {{ relation }} cascade
    {% elif relation.type == 'materialized_view' %}
      drop materialized view if exists {{ relation }} cascade
    {% elif relation.type == 'source' %}
      drop source if exists {{ relation }} cascade
    {% elif relation.type == 'sink' %}
      drop sink if exists {{ relation }} cascade
    {% endif %}
  {%- endcall %}
{% endmacro %}

{% macro risingwave__create_view_as(relation, sql) -%}
  create view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_table_as(relation, sql) -%}
  create table if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_materialized_view_as(relation, sql) -%}
  create materialized view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_sink(relation, sql) -%}
    {%- set _format_parameters = config.get("format_parameters") -%}
    {%- set data_format = config.get("data_format") -%}
    {%- set data_encode = config.get("data_encode") -%}

    {%- set _connector_parameters = config.require("connector_parameters") -%}
    {%- set connector = config.require("connector") -%}

    create sink if not exists {{ relation }}
      {% if "select" in sql.lower() -%}
        as {{ sql }}
      {%- else -%}
        from {{ sql }}
      {%- endif %}
    with (
          connector = '{{ connector }}',
          {%- for key, value in _connector_parameters.items() %}
          {{ key }} = '{{ value }}'
          {%- if not loop.last -%},{%- endif -%}
          {% endfor %}
      )
    {% if _format_parameters and data_format and data_encode -%}
    format {{ data_format }} encode {{ data_encode }} (
    {%- for key, value in _format_parameters.items() %}
          {{ key }} = '{{ value }}'
          {%- if not loop.last -%},{%- endif -%}
          {% endfor %}
    )
    {%- endif -%}
    ;
{%- endmacro %}

{% macro risingwave__run_sql(sql) -%}
  {% set contract_config = config.get('contract') %}
  {% if contract_config.enforced %}
    {{exceptions.warn("Model contracts cannot be enforced for source, table_with_connector and sink")}}
  {%- endif %}
  {{ sql }};
{%- endmacro %}

{%- macro risingwave__update_indexes_on_materialized_view(relation, index_changes) -%}
    {{- log("Applying UPDATE INDEXES to: " ~ relation) -}}

    {%- for _index_change in index_changes -%}
        {%- set _index = _index_change.context -%}

        {%- if _index_change.action == "drop" -%}

            {{ risingwave__get_drop_index_sql(relation, _index.name) }};

        {%- elif _index_change.action == "create" -%}

            {{ risingwave__get_create_index_sql(relation, _index.as_node_config) }}

        {%- endif -%}

    {%- endfor -%}

{%- endmacro -%}

{% macro risingwave__get_show_indexes_sql(relation) %}
    with index_info as (
    select
        i.relname                                   as name,
        'btree'                                     as method,
        ix.indisunique                              as "unique",
        a.attname                                   as attname,
        array_position(ix.indkey, a.attnum)        as ord
    from pg_index ix
    join pg_class i
        on i.oid = ix.indexrelid
    join pg_class t
        on t.oid = ix.indrelid
    join pg_namespace n
        on n.oid = t.relnamespace
    join pg_attribute a
        on a.attrelid = t.oid
        and a.attnum = ANY(ix.indkey)
    where t.relname = '{{ relation.identifier }}'
      and n.nspname = '{{ relation.schema }}'
      and t.relkind in ('r', 'm')
    )
    select name, method, "unique", array_to_string(array_agg(attname order by ord), ',') as column_names from index_info
    group by 1, 2, 3
    order by 1, 2, 3;
{% endmacro %}

{% macro risingwave__execute_no_op(target_relation) %}
    {% do store_raw_result(
        name="main",
        message="skip " ~ target_relation,
        code="skip",
        rows_affected="-1"
    ) %}
{% endmacro %}

{% macro risingwave__handle_on_configuration_change(old_relation, target_relation) %}
    {#
    This macro is used to handle the `on_configuration_change` configuration option.
    It works both for `table_with_connector`, `table` and `materialized_view` materializations.
    #}

    {% set on_configuration_change = config.get('on_configuration_change', "continue") %}
    {% set configuration_changes = get_materialized_view_configuration_changes(old_relation, config) %}

    {% if configuration_changes is none %}
      -- do nothing
      {{ risingwave__execute_no_op(target_relation) }}
    {% elif on_configuration_change == 'apply' %}
      {% call statement('main') -%}
        {{ risingwave__update_indexes_on_materialized_view(target_relation, configuration_changes.indexes) }}
      {%- endcall %}
    {% elif on_configuration_change == 'continue' %}
        -- do nothing but a warning
        {{ exceptions.warn("Configuration changes were identified and `on_configuration_change` was set to `continue` for {}".format(target_relation)) }}
        {{ risingwave__execute_no_op(target_relation) }}
    {% elif on_configuration_change == 'fail' %}
        {{ exceptions.raise_fail_fast_error("Configuration changes were identified and `on_configuration_change` was set to `fail` for {}".format(target_relation)) }}
    {% else %}
        -- this only happens if the user provides a value other than `apply`, 'continue', 'fail'
        {{ exceptions.raise_compiler_error("Unexpected configuration scenario") }}
    {% endif %}
{% endmacro %}
