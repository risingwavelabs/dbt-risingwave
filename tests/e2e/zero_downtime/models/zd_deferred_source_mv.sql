{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

{{ config(
    alias='zd_deferred_a_mv',
    materialized='materialized_view',
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': false
    }
) }}

select
    cast(1 as int) as id,
    cast({% if stage == 'initial' %}10{% else %}100{% endif %} as int) as amount,
    cast('{{ stage }}' as varchar) as deploy_stage
