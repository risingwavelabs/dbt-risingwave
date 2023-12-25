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


-- temporary disable temp table for lacking support to rename table
{% macro risingwave__make_temp_relation(base_relation, suffix) %}
    {%- set temp_identifier = base_relation.identifier -%}
    {%- set temp_relation = base_relation.incorporate(
                                path={"identifier": temp_identifier}) -%}

    {{ return(temp_relation) }}
{% endmacro %}

{% macro risingwave__make_intermediate_relation(base_relation, suffix) %}
    {{ return(make_temp_relation(base_relation, suffix)) }}
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
    {% elif relation.type == 'index' %}
      drop index if exists {{ relation }} cascade
    {% endif %}
  {%- endcall %}
{% endmacro %}

{% macro risingwave__create_view_as(relation, sql) -%}
  create view if not exists {{ relation }} 
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__create_table_as(relation, sql) -%}
  create table if not exists {{ relation }} 
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__create_materialized_view_as(relation, sql) -%}
  create materialized view if not exists {{ relation }} 
    {% set contract_config = config.get('contract') %}
    {% if contract_config.enforced %}
      {{ get_assert_columns_equivalent(sql) }}
    {%- endif %}
  as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__run_sql(sql) -%}
  {% set contract_config = config.get('contract') %}
  {% if contract_config.enforced %}
    {{exceptions.warn("Model contracts cannot be enforced for source, table_with_connector and sink")}}
  {%- endif %}
  {{ sql }};
{%- endmacro %}
