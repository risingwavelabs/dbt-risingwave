{% macro store_failures_results_relation() %}
  {% set audit_schema = target.schema ~ '_dbt_test__audit' %}
  {{ return(api.Relation.create(
      identifier='store_failures_results',
      schema=audit_schema,
      database=target.database,
      type='materialized_view'
  )) }}
{% endmacro %}

{% macro assert_store_failures_results() %}
  {% set relation = store_failures_results_relation() %}

  {% set relation_sql %}
    select rw_relations.relation_type
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ relation.schema }}'
      and rw_relations.name = '{{ relation.identifier }}'
  {% endset %}

  {% set relation_results = run_query(relation_sql) %}

  {% if execute %}
    {% if relation_results is none or relation_results.rows | length != 1 %}
      {{ exceptions.raise_compiler_error(relation.identifier ~ ' relation was not created') }}
    {% endif %}

    {% set relation_type = relation_results.rows[0][0] %}
    {% if relation_type != 'materialized view' %}
      {{ exceptions.raise_compiler_error(relation.identifier ~ ' relation has wrong type: ' ~ relation_type) }}
    {% endif %}

    {% set row_count_sql %}
      select count(*) as row_count
      from {{ relation }}
    {% endset %}

    {% set row_count_results = run_query(row_count_sql) %}
    {% set row_count = row_count_results.rows[0][0] %}
    {% if row_count != 1 %}
      {{ exceptions.raise_compiler_error(relation.identifier ~ ' row count mismatch: ' ~ row_count) }}
    {% endif %}

    {% set expected_row_sql %}
      select 1
      from {{ relation }}
      where id = 2 and status = 'bad'
    {% endset %}

    {% set expected_row_results = run_query(expected_row_sql) %}
    {% if expected_row_results is none or expected_row_results.rows | length != 1 %}
      {{ exceptions.raise_compiler_error(relation.identifier ~ ' missing expected failure row') }}
    {% endif %}
  {% endif %}
{% endmacro %}
