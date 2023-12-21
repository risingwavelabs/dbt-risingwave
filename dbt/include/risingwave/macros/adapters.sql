-- The original postgres adapter only queries tables and views without index.
-- But materialize verison includes 'index' type.
-- Here we only query table, view, materialized view and source. (without index and SINK)
{% macro risingwave__list_relations_without_caching(schema_relation) %}
  {% call statement('list_relations_without_caching', fetch_result=True) -%}
    SELECT
      '{{ schema_relation.database }}' as database,
      cls.relname AS name,
      nsp.nspname AS schema,
      CASE WHEN relkind = 'x' THEN
        'source'
      WHEN relkind = 'm' THEN
        'materializedview'
      WHEN relkind = 'v' THEN
        'view'
      WHEN relkind = 'r' THEN
        'table'
      END AS type
    FROM
      pg_class cls, pg_namespace nsp
    WHERE
      nsp.oid = cls.relnamespace
      AND nsp.nspname NOT in('rw_catalog', 'information_schema', 'pg_catalog')
      AND lower(nsp.nspname) = lower('{{ schema_relation.schema }}'); -- workaround lacking of `ILIKE`
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

{% macro risingwave__drop_relation(relation) -%}
  {% call statement('drop_relation') -%}
    {% if relation.type == 'view' %}
      drop view if exists {{ relation }} cascade
    {% elif relation.type == 'table' %}
      drop table if exists {{ relation }} cascade
    {% elif relation.type == 'materializedview' %}
      drop materialized view if exists {{ relation }} cascade
    {% elif relation.type == 'index' %}
      drop index if exists {{ relation }} cascade
    {% endif %}
  {%- endcall %}
{% endmacro %}

{% macro risingwave__drop_source_cascade(relation) -%}
  {% call statement('drop_relation') -%}
    drop source if exists {{ relation }} cascade
  {%- endcall %}
{% endmacro %}

{% macro risingwave__create_view_as(relation, sql) -%}
  create view {{ relation }} as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__create_table_as(relation, sql) -%}
  create table {{ relation }} as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__create_materialized_view_as(relation, sql) -%}
  create materialized view {{ relation }} as ( 
    {{ sql }} 
  );
{%- endmacro %}

{% macro risingwave__create_source_as(sql) -%}
  {{ sql }};
{%- endmacro %}
