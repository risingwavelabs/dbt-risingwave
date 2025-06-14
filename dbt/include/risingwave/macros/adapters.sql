-- The original postgres adapter only queries tables and views without index.
-- But materialize verison includes 'index' type.
-- Here we only query table, view, materialized view and source. (without index and SINK)
{% macro risingwave__list_relations_without_caching(schema_relation) %}
  {% call statement('list_relations_without_caching', fetch_result=True) -%}
    select
    '{{ schema_relation.database }}' as database,
    rw_relations.name as name,
    rw_schemas.name as schema,
    FIRST_VALUE(CASE WHEN relation_type = 'materialized view' THEN
      'materialized_view'
      else relation_type
    END order by relation_type desc) AS type
    from rw_relations join rw_schemas on schema_id=rw_schemas.id
    where rw_schemas.name not in ('rw_catalog', 'information_schema', 'pg_catalog')
    and relation_type in ('table', 'view', 'source', 'sink', 'materialized view', 'index')
    AND rw_schemas.name = '{{ schema_relation.schema }}'
    group by database, name, schema
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

{% macro risingwave__get_index_name(name, columns) -%}
    {{ return("__dbt_index_{}_{}".format(name, "_".join(columns))) }}
{% endmacro %}

{% macro risingwave__get_create_index_sql(relation, index_dict) -%}
  {%- set index_config = adapter.parse_index(index_dict) -%}
  {%- set comma_separated_columns = ", ".join(index_config.columns) -%}
  {%- set index_name = risingwave__get_index_name(relation.identifier, index_config.columns) -%}

  create index if not exists
  "{{ index_name }}"
  on {{ relation }}
  ({{ comma_separated_columns }});
{%- endmacro %}

{%- macro risingwave__get_drop_index_sql(name, columns) -%}
    {%- set index_name = risingwave__get_index_name(name, columns) -%}
    drop index if exists "{{ index_name }}";
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
    {%- set sql_header = config.get("sql_header", none) -%}
    {{ sql_header if sql_header is not none }}

  create view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_table_as(relation, sql) -%}
    {%- set sql_header = config.get("sql_header", none) -%}
    {{ sql_header if sql_header is not none }}

  create table if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_materialized_view_as(relation, sql) -%}
    {%- set sql_header = config.get("sql_header", none) -%}
    {{ sql_header if sql_header is not none }}

  create materialized view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{% macro risingwave__create_sink(relation, sql) -%}
    {%- set sql_header = config.get("sql_header", none) -%}
    {{ sql_header if sql_header is not none }}

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

            {{ risingwave__get_drop_index_sql(_index.name, _index.column_names) }};

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
      and ix.indisprimary = false
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

{% macro risingwave__truncate_relation(relation) -%}
  {% call statement('truncate_relation') -%}
    delete from {{ relation }}
  {%- endcall %}
{% endmacro %}

{%- macro risingwave__create_materialized_view_with_temp_name(temp_relation, sql) -%}
    {%- set sql_header = config.get("sql_header", none) -%}
    {{ sql_header if sql_header is not none }}

  create materialized view {{ temp_relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{%- macro risingwave__swap_materialized_views(old_relation, new_relation) -%}
  alter materialized view {{ old_relation }} swap with {{ new_relation }}
{%- endmacro %}

{%- macro risingwave__list_temp_materialized_views(schema_name=none) -%}
  {%- if schema_name -%}
    {%- set schema_filter = "AND rw_schemas.name = '" ~ schema_name ~ "'" -%}
  {%- else -%}
    {%- set schema_filter = "" -%}
  {%- endif -%}

  {% call statement('list_temp_mvs', fetch_result=True) -%}
    SELECT 
      rw_schemas.name as schema_name,
      rw_relations.name as mv_name,
      rw_relations.id as mv_id
    FROM rw_relations 
    JOIN rw_schemas ON schema_id = rw_schemas.id
    WHERE rw_schemas.name NOT IN ('rw_catalog', 'information_schema', 'pg_catalog')
      AND relation_type = 'materialized view'
      AND rw_relations.name LIKE '%_dbt_zero_down_tmp_%'
      {{ schema_filter }}
    ORDER BY rw_schemas.name, rw_relations.name
  {%- endcall %}

  {{ return(load_result('list_temp_mvs').table) }}
{%- endmacro %}

{%- macro risingwave__cleanup_temp_materialized_views(schema_name=none, older_than_hours=24, dry_run=true) -%}
  {%- set temp_mvs = risingwave__list_temp_materialized_views(schema_name) -%}
  {%- set cleaned_count = 0 -%}
  
  {% if temp_mvs %}
    {{ print("Found " ~ temp_mvs | length ~ " temporary materialized views") }}
    
    {% for temp_mv in temp_mvs %}
      {%- set mv_relation = api.Relation.create(
          identifier=temp_mv[1],
          schema=temp_mv[0],
          database=database,
          type='materialized_view'
      ) -%}
      
      {% if dry_run %}
        {{ print("DRY RUN: Would drop " ~ mv_relation) }}
      {% else %}
        {{ print("Dropping temporary materialized view: " ~ mv_relation) }}
        {% call statement('drop_temp_mv_' ~ loop.index) -%}
          DROP MATERIALIZED VIEW IF EXISTS {{ mv_relation }} CASCADE
        {%- endcall %}
        {%- set cleaned_count = cleaned_count + 1 -%}
      {% endif %}
    {% endfor %}
    
    {% if not dry_run %}
      {{ print("Cleaned up " ~ cleaned_count ~ " temporary materialized views") }}
    {% endif %}
  {% else %}
    {{ print("No temporary materialized views found") }}
  {% endif %}
{%- endmacro %}

{#-- User-friendly wrapper macros for dbt run-operation --#}

{%- macro list_temp_mvs(schema_name=none) -%}
  {{ print("=== Listing Temporary Materialized Views ===") }}
  {%- if schema_name -%}
    {{ print("Schema: " ~ schema_name) }}
  {%- else -%}
    {{ print("Schema: All schemas") }}
  {%- endif -%}
  {{ print("") }}
  
  {%- set temp_mvs = risingwave__list_temp_materialized_views(schema_name) -%}
  
  {% if temp_mvs %}
    {{ print("Found " ~ temp_mvs | length ~ " temporary materialized views:") }}
    {% for temp_mv in temp_mvs %}
      {{ print("  - " ~ temp_mv[0] ~ "." ~ temp_mv[1]) }}
    {% endfor %}
  {% else %}
    {{ print("No temporary materialized views found.") }}
  {% endif %}
  {{ print("") }}
{%- endmacro %}

{%- macro cleanup_temp_mvs(schema_name=none, execute=false) -%}
  {{ print("=== Temporary Materialized Views Cleanup ===") }}
  {%- if schema_name -%}
    {{ print("Schema: " ~ schema_name) }}
  {%- else -%}
    {{ print("Schema: All schemas") }}
  {%- endif -%}
  {{ print("Mode: " ~ ("EXECUTE" if execute else "DRY RUN")) }}
  {{ print("") }}
  
  {{ risingwave__cleanup_temp_materialized_views(schema_name=schema_name, dry_run=(not execute)) }}
  
  {% if not execute %}
    {{ print("") }}
    {{ print("To actually clean up these temporary MVs, run:") }}
    {% if schema_name %}
      {{ print('dbt run-operation cleanup_temp_mvs --args \'{"schema_name": "' ~ schema_name ~ '", "execute": true}\'') }}
    {% else %}
      {{ print('dbt run-operation cleanup_temp_mvs --args \'{"execute": true}\'') }}
    {% endif %}
  {% endif %}
{%- endmacro %}
