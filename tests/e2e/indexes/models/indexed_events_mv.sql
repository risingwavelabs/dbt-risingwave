{% set index_stage = env_var('DBT_RW_INDEX_STAGE', 'initial') %}

{% if index_stage == 'initial' %}
  {% set index_config = {
      'columns': ['user_id'],
      'include': ['event_type'],
      'distributed_by': ['user_id']
  } %}
{% elif index_stage == 'changed' %}
  {% set index_config = {
      'columns': ['event_type'],
      'include': ['user_id'],
      'distributed_by': ['event_type']
  } %}
{% else %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_INDEX_STAGE: " ~ index_stage) }}
{% endif %}

{{ config(
    materialized='materialized_view',
    indexes=[index_config],
    on_configuration_change='apply',
    background_ddl=true
) }}

select
    cast(1 as int) as event_id,
    cast(101 as int) as user_id,
    cast('click' as varchar) as event_type
union all
select
    cast(2 as int) as event_id,
    cast(202 as int) as user_id,
    cast('purchase' as varchar) as event_type
