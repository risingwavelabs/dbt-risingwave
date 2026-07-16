{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage == 'initial' %}
  {% set index_configs = [
      {
        'columns': ['id'],
        'include': ['payload'],
        'distributed_by': ['id']
      },
      {
        'columns': ['deploy_stage'],
        'include': ['id'],
        'distributed_by': ['deploy_stage']
      }
  ] %}
{% elif stage == 'changed' %}
  {% set index_configs = [
      {
        'columns': ['id'],
        'include': ['deploy_stage'],
        'distributed_by': ['id']
      },
      {
        'columns': ['payload'],
        'include': ['id'],
        'distributed_by': ['payload']
      }
  ] %}
{% else %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

{{ config(
    materialized='materialized_view',
    indexes=index_configs,
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': false
    }
) }}

select
    cast(1 as int) as id,
    cast('{{ stage }}_indexed_alpha' as varchar) as payload,
    cast('{{ stage }}' as varchar) as deploy_stage
union all
select
    cast(2 as int) as id,
    cast('{{ stage }}_indexed_beta' as varchar) as payload,
    cast('{{ stage }}' as varchar) as deploy_stage
