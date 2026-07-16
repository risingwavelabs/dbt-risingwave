{% set expected_stage = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE', 'initial') %}
{% set expect_temp_cleaned = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_TEMP_CLEANED', 'false') == 'true' %}

{% if expected_stage == 'changed' and not expect_temp_cleaned %}
  {% set expected_immediate_temps = 2 %}
  {% set expected_deferred_temps = 3 %}
{% else %}
  {% set expected_immediate_temps = 0 %}
  {% set expected_deferred_temps = 0 %}
{% endif %}

select 'immediate-cleanup chain has an unexpected temporary object count' as failure
where (
    select count(*)
    from rw_catalog.rw_relations r
    join rw_catalog.rw_schemas s on s.id = r.schema_id
    where s.name = '{{ target.schema }}'
      and r.name like 'zd_immediate_%_dbt_zero_down_tmp_%'
) != {{ expected_immediate_temps }}

union all

select 'deferred-cleanup chain has an unexpected temporary object count' as failure
where (
    select count(*)
    from rw_catalog.rw_relations r
    join rw_catalog.rw_schemas s on s.id = r.schema_id
    where s.name = '{{ target.schema }}'
      and r.name like 'zd_deferred_%_dbt_zero_down_tmp_%'
) != {{ expected_deferred_temps }}

union all

select 'deferred-cleanup chain did not expose the expected rebuilt result' as failure
where not exists (
    select 1
    from {{ ref('zd_deferred_final_mv') }}
    where id = 1
      and final_amount = {% if expected_stage == 'initial' %}21{% else %}201{% endif %}
      and deploy_stage = '{{ expected_stage }}'
)
