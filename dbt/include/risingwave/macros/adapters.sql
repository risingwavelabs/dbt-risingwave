-- The original postgres adapter only queries tables and views without index.
-- But materialize verison includes 'index' type.
-- Here we only query table, view, materialized view and source. (without index and SINK)

{% macro risingwave__render_sql_header() -%}
  {%- set header_parts = [] -%}
  {%- set user_header = config.get("sql_header", none) -%}
  {%- if user_header is not none -%}
    {%- do header_parts.append(user_header) -%}
  {%- endif -%}

  {%- set background_ddl = config.get("background_ddl", false) -%}
  {%- if background_ddl -%}
    {%- do header_parts.append("set background_ddl = true;") -%}
  {%- endif -%}

  {%- set streaming_parallelism = config.get("streaming_parallelism", none) -%}
  {%- if streaming_parallelism is not none -%}
    {%- do header_parts.append("set streaming_parallelism = " ~ streaming_parallelism ~ ";") -%}
  {%- endif -%}

  {%- set streaming_parallelism_for_backfill = config.get("streaming_parallelism_for_backfill", none) -%}
  {%- if streaming_parallelism_for_backfill is not none -%}
    {%- do header_parts.append("set streaming_parallelism_for_backfill = " ~ streaming_parallelism_for_backfill ~ ";") -%}
  {%- endif -%}

  {%- set streaming_max_parallelism = config.get("streaming_max_parallelism", none) -%}
  {%- if streaming_max_parallelism is not none -%}
    {%- do header_parts.append("set streaming_max_parallelism = " ~ streaming_max_parallelism ~ ";") -%}
  {%- endif -%}

  {%- set enable_serverless_backfill = config.get("enable_serverless_backfill", none) -%}
  {%- if enable_serverless_backfill is not none -%}
    {%- do header_parts.append("set enable_serverless_backfill = " ~ enable_serverless_backfill | lower ~ ";") -%}
  {%- endif -%}

  {{- header_parts | join("\n") -}}
{%- endmacro %}

{% macro risingwave__list_relations_without_caching(schema_relation) %}
  {% call statement('list_relations_without_caching', fetch_result=True) -%}
    with rw_schema_relations as (
      select
        '{{ schema_relation.database }}' as database,
        rw_relations.name as name,
        rw_schemas.name as schema,
        case
          when relation_type = 'materialized view' then 'materialized_view'
          else relation_type
        end as type
      from rw_relations
      join rw_schemas on schema_id = rw_schemas.id
      where rw_schemas.name not in ('rw_catalog', 'information_schema', 'pg_catalog')
        and relation_type in ('table', 'view', 'source', 'sink', 'materialized view', 'index')
        and rw_schemas.name = '{{ schema_relation.schema }}'
    ),
    rw_schema_functions as (
      select
        '{{ schema_relation.database }}' as database,
        rw_functions.name as name,
        rw_schemas.name as schema,
        'function' as type
      from rw_functions
      join rw_schemas on rw_functions.schema_id = rw_schemas.id
      where rw_schemas.name not in ('rw_catalog', 'information_schema', 'pg_catalog')
        and rw_schemas.name = '{{ schema_relation.schema }}'
      group by database, name, schema
      having count(*) = 1
    )
    select database, name, schema, type
    from rw_schema_relations
    union all
    select database, name, schema, type
    from rw_schema_functions
  {% endcall %}
  {{ return(load_result('list_relations_without_caching').table) }}
{% endmacro %}

{% macro risingwave__create_schema(relation) -%}
  {% if relation.database -%}
    {{ adapter.verify_database(relation.database) }}
  {%- endif -%}

  {%- set schema_owner = none -%}
  {%- if config is defined -%}
    {%- set configured_owner = config.get("schema_authorization", none) -%}
    {%- if configured_owner is not none and configured_owner | trim != "" -%}
      {%- set schema_owner = configured_owner -%}
    {%- endif -%}
  {%- endif -%}

  {%- call statement('create_schema') -%}
    create schema if not exists {{ relation.without_identifier().include(database=False) }}
    {%- if schema_owner %}
      authorization {{ adapter.quote(schema_owner) }}
    {%- endif %}
  {%- endcall -%}
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

{% macro risingwave__alter_relation_comment(relation, comment) %}
  {# RisingWave uses COMMENT ON TABLE for all relation types including materialized views.
     RisingWave does not support dollar-quoting, so we use single-quote escaping. #}
  comment on table {{ relation }} is '{{ comment | replace("'", "''") }}';
{% endmacro %}

{% macro risingwave__alter_column_comment(relation, column_dict) %}
  {# RisingWave only supports schema.table.column (3-part), not database.schema.table.column (4-part) #}
  {% set existing_columns = adapter.get_columns_in_relation(relation) | map(attribute="name") | list %}
  {% for column_name in column_dict if (column_name in existing_columns) %}
    {% set comment = column_dict[column_name]["description"] %}
    {% set col_ref = adapter.quote(column_name) if column_dict[column_name]['quote'] else column_name %}
    comment on column "{{ relation.schema }}"."{{ relation.identifier }}".{{ col_ref }} is '{{ comment | replace("'", "''") }}';
  {% endfor %}
{% endmacro %}

{% macro risingwave__get_index_name(name, columns) -%}
    {{ return("__dbt_index_{}_{}".format(name, "_".join(columns))) }}
{% endmacro %}

{% macro risingwave__get_create_index_sql(relation, index_dict) -%}
  {%- set index_config = adapter.parse_index({"columns": index_dict.get("columns", [])}) -%}
  {%- set comma_separated_columns = ", ".join(index_config.columns) -%}
  {%- set index_name = risingwave__get_index_name(relation.identifier, index_config.columns) -%}

  create index if not exists
  "{{ index_name }}"
  on {{ relation }}
  ({{ comma_separated_columns }})
  {%- if index_dict.get('include', []) | length > 0 %}
  include ({{ ", ".join(index_dict.get('include', [])) }})
  {%- endif %}
  {%- if index_dict.get('distributed_by', []) | length > 0 %}
  distributed by ({{ ", ".join(index_dict.get('distributed_by', [])) }})
  {%- endif %};
{%- endmacro %}

{%- macro risingwave__get_drop_index_sql(relation, index_name) -%}
    {%- set db_name = relation.database -%}
    {%- set schema_name = relation.schema -%}

    drop index if exists
     "{{ db_name }}"."{{ schema_name }}"."{{ index_name }}";
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
    {% elif relation.type == 'function' %}
      drop function if exists {{ relation }}
    {% endif %}
  {%- endcall %}
{% endmacro %}

{% macro risingwave__create_view_as(relation, sql) -%}
    {{ risingwave__render_sql_header() }}

  create view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{# Dispatch-compatible alias (dbt 1.8+) #}
{% macro risingwave__get_create_view_as_sql(relation, sql) -%}
    {{ risingwave__create_view_as(relation, sql) }}
{%- endmacro %}

{% macro risingwave__create_table_as(temporary, relation, sql) -%}
    {# RisingWave does not support temporary tables; the flag is accepted but ignored. #}
    {{ risingwave__render_sql_header() }}

  create table if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{# Dispatch-compatible alias (dbt 1.8+) #}
{% macro risingwave__get_create_table_as_sql(temporary, relation, compiled_code) -%}
    {{ risingwave__create_table_as(temporary, relation, compiled_code) }}
{%- endmacro %}

{% macro risingwave__create_materialized_view_as(relation, sql) -%}
    {{ risingwave__render_sql_header() }}

  create materialized view if not exists {{ relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{# Dispatch-compatible alias (dbt 1.8+) #}
{% macro risingwave__get_create_materialized_view_as_sql(relation, sql) -%}
    {{ risingwave__create_materialized_view_as(relation, sql) }}
{%- endmacro %}

{% macro risingwave__create_sink(relation, sql) -%}
    {{ risingwave__render_sql_header() }}

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
  {{ risingwave__render_sql_header() }}
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
        a.attname                                   as attname,
        array_position(ix.indkey, a.attnum)         as ord
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
        -- Only include the first indnkeyatts columns (the actual index key columns)
        -- The rest are implicit INCLUDE columns in RisingWave
        and array_position(ix.indkey, a.attnum) <= ix.indnkeyatts
    where t.relname = '{{ relation.identifier }}'
      and n.nspname = '{{ relation.schema }}'
      and t.relkind in ('r', 'm')
      and ix.indisprimary = false
    )
    select name, array_to_string(array_agg(attname order by ord), ',') as column_names from index_info
    group by name
    order by name;
{% endmacro %}

{% macro risingwave__execute_no_op(target_relation) %}
    {% do store_raw_result(
        name="main",
        message="skip " ~ target_relation,
        code="skip",
        rows_affected="-1"
    ) %}
{% endmacro %}

{% macro risingwave__background_ddl_enabled() %}
  {{ return(config.get("background_ddl", false)) }}
{% endmacro %}

{% macro risingwave__wait_for_background_ddl(relation, relation_type=none, identifier=none) %}
  {% if not risingwave__background_ddl_enabled() %}
    {{ return("") }}
  {% endif %}
  {% do run_query('WAIT') %}
{% endmacro %}

{% macro risingwave__wait_for_background_indexes(relation) %}
  {% if not risingwave__background_ddl_enabled() %}
    {{ return("") }}
  {% endif %}

  {%- set index_configs = config.get('indexes', []) -%}
  {% if index_configs | length > 0 %}
    {% do run_query('WAIT') %}
  {% endif %}
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
      {{ risingwave__wait_for_background_ddl(target_relation, 'index') }}
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

{% macro risingwave__validate_table_with_connector_on_schema_change(on_schema_change) %}
  {% if on_schema_change is none %}
    {{ return("ignore") }}
  {% elif on_schema_change in ["ignore", "append_new_columns", "fail"] %}
    {{ return(on_schema_change) }}
  {% elif on_schema_change == "sync_all_columns" %}
    {{ exceptions.raise_compiler_error("`table_with_connector` does not support `on_schema_change='sync_all_columns'`. Use `append_new_columns` for additive changes or run explicit RisingWave DDL for non-additive changes.") }}
  {% else %}
    {{ exceptions.raise_compiler_error("Invalid `on_schema_change` value for `table_with_connector`: " ~ on_schema_change) }}
  {% endif %}
{% endmacro %}

{% macro risingwave__get_table_with_connector_additive_columns() %}
  {% set additive_columns = config.get("additive_schema_evolution", none) %}

  {# Alias in case users prefer a materialization-specific config name. #}
  {% if additive_columns is none %}
    {% set additive_columns = config.get("table_with_connector_add_columns", []) %}
  {% endif %}

  {% if additive_columns is mapping %}
    {% set additive_columns = additive_columns.get("columns", []) %}
  {% endif %}

  {% if additive_columns is string %}
    {{ exceptions.raise_compiler_error("`additive_schema_evolution` must be a list of column definitions, not a string.") }}
  {% endif %}

  {{ return(additive_columns) }}
{% endmacro %}

{% macro risingwave__render_table_with_connector_add_column(column_config) -%}
  {% if column_config is not mapping %}
    {{ exceptions.raise_compiler_error("Each `additive_schema_evolution` entry must be a dictionary with `name` and `data_type`.") }}
  {% endif %}

  {% set column_name = column_config.get("name", none) %}
  {% set data_type = column_config.get("data_type", column_config.get("type", none)) %}
  {% set default_expr = column_config.get("default", none) %}
  {% set not_null = column_config.get("not_null", false) %}

  {% if column_name is none or column_name | trim == "" %}
    {{ exceptions.raise_compiler_error("Each `additive_schema_evolution` entry must include a non-empty `name`.") }}
  {% endif %}

  {% if data_type is none or data_type | trim == "" %}
    {{ exceptions.raise_compiler_error("`additive_schema_evolution` column `" ~ column_name ~ "` must include `data_type`.") }}
  {% endif %}

  {% if column_config.get("primary_key", false) %}
    {{ exceptions.raise_compiler_error("`table_with_connector` additive schema evolution cannot add primary-key columns: " ~ column_name) }}
  {% endif %}

  {% if column_config.get("generated", false) %}
    {{ exceptions.raise_compiler_error("`table_with_connector` additive schema evolution cannot add generated columns: " ~ column_name) }}
  {% endif %}

  {% if not_null and default_expr is none %}
    {{ exceptions.raise_compiler_error("`table_with_connector` additive schema evolution cannot add NOT NULL column `" ~ column_name ~ "` without a DEFAULT expression.") }}
  {% endif %}

  {%- if column_config.get("quote", false) -%}
    {{ adapter.quote(column_name) }}
  {%- else -%}
    {{ column_name }}
  {%- endif -%}
  {{ " " ~ data_type }}
  {%- if default_expr is not none %} default {{ default_expr }}{% endif -%}
  {%- if not_null %} not null{% endif -%}
{%- endmacro %}

{% macro risingwave__table_with_connector_missing_additive_columns(target_relation, additive_columns) %}
  {% set existing_column_names = [] %}
  {% for existing_column in adapter.get_columns_in_relation(target_relation) %}
    {% do existing_column_names.append(existing_column.name | lower) %}
  {% endfor %}

  {% set missing_columns = [] %}
  {% for column_config in additive_columns %}
    {% if column_config is not mapping %}
      {{ exceptions.raise_compiler_error("Each `additive_schema_evolution` entry must be a dictionary with `name` and `data_type`.") }}
    {% endif %}

    {% set column_name = column_config.get("name", none) %}
    {% if column_name is none or column_name | trim == "" %}
      {{ exceptions.raise_compiler_error("Each `additive_schema_evolution` entry must include a non-empty `name`.") }}
    {% endif %}

    {% if column_name | lower not in existing_column_names %}
      {% do missing_columns.append(column_config) %}
    {% endif %}
  {% endfor %}

  {{ return(missing_columns) }}
{% endmacro %}

{% macro risingwave__handle_table_with_connector_on_schema_change(target_relation) %}
  {% set on_schema_change = risingwave__validate_table_with_connector_on_schema_change(config.get("on_schema_change", "ignore")) %}

  {% if on_schema_change == "ignore" %}
    {{ return(false) }}
  {% endif %}

  {% set additive_columns = risingwave__get_table_with_connector_additive_columns() %}

  {% if additive_columns | length == 0 %}
    {% if on_schema_change == "append_new_columns" %}
      {{ exceptions.warn("`table_with_connector` cannot infer new columns from raw CREATE TABLE SQL. Configure `additive_schema_evolution` to enable additive schema evolution.") }}
    {% endif %}
    {{ return(false) }}
  {% endif %}

  {% set missing_columns = risingwave__table_with_connector_missing_additive_columns(target_relation, additive_columns) %}

  {% if missing_columns | length == 0 %}
    {{ return(false) }}
  {% elif on_schema_change == "fail" %}
    {% set missing_column_names = missing_columns | map(attribute="name") | join(", ") %}
    {{ exceptions.raise_compiler_error("`table_with_connector` schema changes detected for " ~ target_relation ~ ": missing columns [" ~ missing_column_names ~ "]. Set `on_schema_change='append_new_columns'` to apply additive changes.") }}
  {% elif on_schema_change == "append_new_columns" %}
    {% call statement('table_with_connector_add_columns') -%}
      {% for column_config in missing_columns %}
        alter table {{ target_relation }} add column {{ risingwave__render_table_with_connector_add_column(column_config) }};
      {% endfor %}
    {%- endcall %}
    {{ return(true) }}
  {% endif %}
{% endmacro %}

{% macro risingwave__truncate_relation(relation) -%}
  {% call statement('truncate_relation') -%}
    delete from {{ relation }}
  {%- endcall %}
{% endmacro %}

{%- macro risingwave__create_materialized_view_with_temp_name(temp_relation, sql) -%}
    {{ risingwave__render_sql_header() }}

  create materialized view {{ temp_relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{%- macro risingwave__create_view_with_temp_name(temp_relation, sql) -%}
    {{ risingwave__render_sql_header() }}

  create view {{ temp_relation }}
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as {{ sql }}
  ;
{%- endmacro %}

{%- macro risingwave__swap_views(old_relation, new_relation) -%}
  alter view {{ old_relation }} swap with {{ new_relation }}
{%- endmacro %}

{%- macro risingwave__swap_materialized_views(old_relation, new_relation) -%}
  alter materialized view {{ old_relation }} swap with {{ new_relation }}
{%- endmacro %}





{#-- Unified API for managing all temporary zero downtime objects --#}

{%- macro risingwave__list_temp_objects(schema_name=none, object_types=none) -%}
  {%- if schema_name -%}
    {%- set schema_filter = "AND rw_schemas.name = '" ~ schema_name ~ "'" -%}
  {%- else -%}
    {%- set schema_filter = "" -%}
  {%- endif -%}

  {# Default to all supported object types if none specified #}
  {%- if object_types is none -%}
    {%- set object_types = ['materialized view', 'view'] -%}
  {%- endif -%}
  
  {# Build the type filter #}
  {%- set type_conditions = [] -%}
  {%- for obj_type in object_types -%}
    {%- do type_conditions.append("'" ~ obj_type ~ "'") -%}
  {%- endfor -%}
  {%- set type_filter = "AND relation_type IN (" ~ type_conditions | join(', ') ~ ")" -%}

  {% call statement('list_temp_objects', fetch_result=True) -%}
    SELECT 
      rw_schemas.name as schema_name,
      rw_relations.name as object_name,
      rw_relations.id as object_id,
      relation_type as object_type
    FROM rw_relations 
    JOIN rw_schemas ON schema_id = rw_schemas.id
    WHERE rw_schemas.name NOT IN ('rw_catalog', 'information_schema', 'pg_catalog')
      {{ type_filter }}
      AND rw_relations.name LIKE '%_dbt_zero_down_tmp_%'
      {{ schema_filter }}
    ORDER BY rw_schemas.name, relation_type, rw_relations.name
  {%- endcall %}

  {{ return(load_result('list_temp_objects').table) }}
{%- endmacro %}

{%- macro risingwave__cleanup_temp_objects(schema_name=none, object_types=none, older_than_hours=24, dry_run=true) -%}
  {%- set temp_objects = risingwave__list_temp_objects(schema_name, object_types) -%}
  
  {% if temp_objects %}
    {{ print("Found " ~ temp_objects | length ~ " temporary objects") }}
    
    {% for temp_obj in temp_objects %}
      {%- set obj_type_mapping = {
          'materialized view': 'materialized_view',
          'view': 'view',
          'sink': 'sink'
      } -%}
      {%- set dbt_type = obj_type_mapping.get(temp_obj[3], temp_obj[3]) -%}
      
      {%- set obj_relation = api.Relation.create(
          identifier=temp_obj[1],
          schema=temp_obj[0],
          database=database,
          type=dbt_type
      ) -%}
      
      {% if dry_run %}
        {{ print("DRY RUN: Would drop " ~ temp_obj[3] ~ " " ~ obj_relation) }}
      {% else %}
        {{ print("Dropping temporary " ~ temp_obj[3] ~ ": " ~ obj_relation) }}
        {% call statement('drop_temp_obj_' ~ loop.index) -%}
          {% if temp_obj[3] == 'materialized view' %}
            DROP MATERIALIZED VIEW IF EXISTS {{ obj_relation }} CASCADE
          {% elif temp_obj[3] == 'view' %}
            DROP VIEW IF EXISTS {{ obj_relation }} CASCADE
          {% elif temp_obj[3] == 'sink' %}
            DROP SINK IF EXISTS {{ obj_relation }} CASCADE
          {% endif %}
        {%- endcall %}
      {% endif %}
    {% endfor %}
    
    {% if not dry_run %}
      {{ print("Finished cleaning up temporary objects") }}
    {% endif %}
  {% else %}
    {{ print("No temporary objects found") }}
  {% endif %}
{%- endmacro %}

{#-- User-friendly unified wrapper macros --#}

{%- macro list_temp_objects(schema_name=none, object_types=none) -%}
  {{ print("=== Listing Temporary Zero Downtime Objects ===") }}
  {%- if schema_name -%}
    {{ print("Schema: " ~ schema_name) }}
  {%- else -%}
    {{ print("Schema: All schemas") }}
  {%- endif -%}
  
  {%- if object_types -%}
    {{ print("Object Types: " ~ (object_types | join(', '))) }}
  {%- else -%}
    {{ print("Object Types: All supported types (materialized views, views)") }}
  {%- endif -%}
  {{ print("") }}
  
  {%- set temp_objects = risingwave__list_temp_objects(schema_name, object_types) -%}
  
  {% if temp_objects %}
    {{ print("Found " ~ temp_objects | length ~ " temporary objects:") }}
    
    {# Group by object type for better readability #}
    {%- set objects_by_type = {} -%}
    {% for temp_obj in temp_objects %}
      {%- set obj_type = temp_obj[3] -%}
      {%- if obj_type not in objects_by_type -%}
        {%- do objects_by_type.update({obj_type: []}) -%}
      {%- endif -%}
      {%- do objects_by_type[obj_type].append(temp_obj) -%}
    {% endfor %}
    
    {% for obj_type, objects in objects_by_type.items() %}
      {{ print("") }}
      {{ print(obj_type | title ~ "s (" ~ objects | length ~ "):") }}
      {% for obj in objects %}
        {{ print("  - " ~ obj[0] ~ "." ~ obj[1]) }}
      {% endfor %}
    {% endfor %}
  {% else %}
    {{ print("No temporary objects found.") }}
  {% endif %}
  {{ print("") }}
{%- endmacro %}

{%- macro cleanup_temp_objects(schema_name=none, object_types=none, dry=false) -%}
  {{ print("=== Temporary Zero Downtime Objects Cleanup ===") }}
  {%- if schema_name -%}
    {{ print("Schema: " ~ schema_name) }}
  {%- else -%}
    {{ print("Schema: All schemas") }}
  {%- endif -%}
  
  {%- if object_types -%}
    {{ print("Object Types: " ~ (object_types | join(', '))) }}
  {%- else -%}
    {{ print("Object Types: All supported types") }}
  {%- endif -%}
  {{ print("Mode: " ~ ("DRY RUN" if dry else "EXECUTE")) }}
  {{ print("") }}
  
  {{ risingwave__cleanup_temp_objects(schema_name=schema_name, object_types=object_types, dry_run=dry) }}
  
  {% if dry %}
    {{ print("") }}
    {{ print("To actually clean up these temporary objects, run:") }}
    {% if schema_name and object_types %}
      {{ print('dbt run-operation cleanup_temp_objects --args \'{"schema_name": "' ~ schema_name ~ '", "object_types": ["' ~ (object_types | join('", "')) ~ '"]}\'') }}
    {% elif schema_name %}
      {{ print('dbt run-operation cleanup_temp_objects --args \'{"schema_name": "' ~ schema_name ~ '"}\'') }}
    {% elif object_types %}
      {{ print('dbt run-operation cleanup_temp_objects --args \'{"object_types": ["' ~ (object_types | join('", "')) ~ '"]}\'') }}
    {% else %}
      {{ print('dbt run-operation cleanup_temp_objects') }}
    {% endif %}
  {% endif %}
{%- endmacro %}
