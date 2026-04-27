{% macro incremental_source_relation() %}
  {{ return(api.Relation.create(
      identifier='incremental_input',
      schema=target.schema,
      database=target.database,
      type='table'
  )) }}
{% endmacro %}

{% macro setup_initial_incremental_source() %}
  {% set relation = incremental_source_relation() %}

  {% call statement('setup_initial_incremental_source') %}
    drop table if exists {{ relation }};
    create table {{ relation }} (
      id int,
      payload varchar,
      batch_id int
    );
    insert into {{ relation }} values
      (1, 'alpha', 1),
      (2, 'beta', 1);
  {% endcall %}
{% endmacro %}

{% macro append_incremental_source() %}
  {% set relation = incremental_source_relation() %}

  {% call statement('append_incremental_source') %}
    insert into {{ relation }} values
      (3, 'gamma', 2);
  {% endcall %}
{% endmacro %}

{% macro reset_incremental_source_for_full_refresh() %}
  {% set relation = incremental_source_relation() %}

  {% call statement('reset_incremental_source_for_full_refresh') %}
    drop table if exists {{ relation }};
    create table {{ relation }} (
      id int,
      payload varchar,
      batch_id int
    );
    insert into {{ relation }} values
      (10, 'reset_alpha', 3),
      (11, 'reset_beta', 3);
  {% endcall %}
{% endmacro %}
