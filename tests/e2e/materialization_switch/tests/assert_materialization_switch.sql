{% set expected_stage = env_var('DBT_RW_MATERIALIZATION_SWITCH_EXPECT_STAGE', 'initial') %}

{% if expected_stage not in ['initial', 'switched'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_MATERIALIZATION_SWITCH_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

{% if expected_stage == 'initial' %}
  {% set expected_types = {
    'ms_view_to_mv': 'view',
    'ms_mv_to_view': 'materialized view',
    'ms_view_to_table': 'view',
    'ms_table_to_mv': 'table',
    'ms_mv_to_table': 'materialized view',
    'ms_guarded': 'materialized view',
    'ms_guarded_child': 'materialized view',
  } %}
{% else %}
  {#- ms_guarded keeps its type: the switch is refused because ms_guarded_child depends on it. -#}
  {% set expected_types = {
    'ms_view_to_mv': 'materialized view',
    'ms_mv_to_view': 'view',
    'ms_view_to_table': 'table',
    'ms_table_to_mv': 'materialized view',
    'ms_mv_to_table': 'table',
    'ms_guarded': 'materialized view',
    'ms_guarded_child': 'materialized view',
  } %}
{% endif %}

with actual as (
    select rw_relations.name, rw_relations.relation_type
    from rw_catalog.rw_relations
    join rw_catalog.rw_schemas on rw_relations.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
)

{% for model_name, relation_type in expected_types.items() %}
{% if not loop.first %}union all{% endif %}

select '{{ model_name }} is not a {{ relation_type }}' as failure
where not exists (
    select 1 from actual
    where name = '{{ model_name }}' and relation_type = '{{ relation_type }}'
)

union all

select '{{ model_name }} also exists with another type' as failure
where exists (
    select 1 from actual
    where name = '{{ model_name }}' and relation_type not in ('{{ relation_type }}', 'index')
)

union all

select '{{ model_name }} row count mismatch' as failure
where (select count(*) from {{ ref(model_name) }}) != 2
{% endfor %}

{% if expected_stage == 'switched' %}
union all

select 'ms_table_to_mv lost its index after the switch' as failure
where not exists (
    select 1
    from rw_catalog.rw_indexes
    join rw_catalog.rw_relations on rw_indexes.primary_table_id = rw_relations.id
    join rw_catalog.rw_schemas on rw_relations.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'ms_table_to_mv'
      and rw_relations.relation_type = 'materialized view'
)
{% endif %}
