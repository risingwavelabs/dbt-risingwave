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
      pg_class cls
      JOIN pg_namespace nsp
    WHERE
      nsp.oid = cls.relnamespace
      AND nsp.nspname NOT in('rw_catalog', 'information_schema', 'pg_catalog')
      AND lower(nsp.nspname) = lower('{{ schema_relation.schema }}'); -- workaround lacking of `ILIKE`
  {% endcall %}
  {{ return(load_result('list_relations_without_caching').table) }}
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