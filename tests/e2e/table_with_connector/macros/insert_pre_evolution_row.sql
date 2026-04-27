{% macro insert_pre_evolution_row() %}
  {% set relation = api.Relation.create(
      identifier='connector_events',
      schema=target.schema,
      database=target.database,
      type='table'
  ) %}

  {% call statement('insert_pre_evolution_row') %}
    insert into {{ relation }} values (101, 'before_add_column');
  {% endcall %}
{% endmacro %}
