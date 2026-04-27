{% set enable_additive_columns = env_var('DBT_RW_TWC_ADD_EXTRA', 'false') == 'true' %}
{% set on_schema_change = 'append_new_columns' if enable_additive_columns else 'ignore' %}
{% if enable_additive_columns %}
  {% set additive_columns = [
      {'name': 'source_tag', 'data_type': 'varchar'},
      {'name': 'score', 'data_type': 'integer'}
  ] %}
{% else %}
  {% set additive_columns = [] %}
{% endif %}

{{ config(
    materialized='table_with_connector',
    on_schema_change=on_schema_change,
    additive_schema_evolution=additive_columns
) }}

CREATE TABLE {{ this }} (
    id int,
    payload varchar
    {% if enable_additive_columns -%}
    , source_tag varchar
    , score int
    {%- endif %}
) WITH (
    appendonly = 'true'
);
