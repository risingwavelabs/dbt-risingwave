{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

{#- Switches from a view to a materialized view in the changed stage (#166). -#}
{{ config(
    materialized=('view' if stage == 'initial' else 'materialized_view'),
    grants={'select': ['dbt_e2e_zd_grantee']},
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': true
    }
) }}

select
    cast(1 as int) as id,
    cast('{{ stage }}' as varchar) as deploy_stage
union all
select
    cast(2 as int) as id,
    cast('{{ stage }}' as varchar) as deploy_stage
