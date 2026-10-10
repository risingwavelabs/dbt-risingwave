{% set expected_stage = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE', 'initial') %}

{% if expected_stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

{% set expected_types = {
  'zd_switch_view_to_mv': 'view' if expected_stage == 'initial' else 'materialized view',
  'zd_switch_mv_to_view': 'materialized view' if expected_stage == 'initial' else 'view',
} %}

{% for model_name, relation_type in expected_types.items() %}
{% if not loop.first %}union all{% endif %}

select '{{ model_name }} must be a {{ relation_type }}' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = '{{ model_name }}'
      and rw_relations.relation_type = '{{ relation_type }}'
)

union all

select '{{ model_name }} must expose the {{ expected_stage }} rows' as failure
where (
    select count(*) from {{ ref(model_name) }} where deploy_stage = '{{ expected_stage }}'
) != 2

union all

-- immediate_cleanup drops the replaced relation, whatever its type.
select '{{ model_name }} left a zero-downtime temp relation behind' as failure
where exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name like '{{ model_name }}\_dbt\_zero\_down\_tmp\_%'
)
{% endfor %}
