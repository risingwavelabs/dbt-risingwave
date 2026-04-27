{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

{{ config(
    materialized='view',
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': true
    }
) }}

select
    cast(1 as int) as id,
    cast('{{ stage }}_view_alpha' as varchar) as payload
union all
select
    cast(2 as int) as id,
    cast('{{ stage }}_view_beta' as varchar) as payload
