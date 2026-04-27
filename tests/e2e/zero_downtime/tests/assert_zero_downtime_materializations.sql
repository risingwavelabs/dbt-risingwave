{% set expected_stage = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE', 'initial') %}

{% if expected_stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

select 'zd_base_view must be a view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'zd_base_view'
      and rw_relations.relation_type = 'view'
)

union all

select 'zd_events_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'zd_events_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'zd_chain_source_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'zd_chain_source_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'zd_chain_middle_mv must be a materialized view after zero-downtime swap' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'zd_chain_middle_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'zd_chain_final_mv must be a materialized view after upstream zero-downtime swap' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'zd_chain_final_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'zero-downtime temp relations should be cleaned up' as failure
where exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name like '%_dbt_zero_down_tmp_%'
)

union all

select 'zd_base_view has unexpected row count' as failure
where (select count(*) from {{ ref('zd_base_view') }}) != 2

union all

select 'zd_base_view missing alpha row for expected stage' as failure
where not exists (
    select 1
    from {{ ref('zd_base_view') }}
    where id = 1 and payload = '{{ expected_stage }}_view_alpha'
)

union all

select 'zd_base_view still exposes stale rows after swap' as failure
where exists (
    select 1
    from {{ ref('zd_base_view') }}
    where payload not like '{{ expected_stage }}_%'
)

union all

select 'zd_events_mv has unexpected row count' as failure
where (select count(*) from {{ ref('zd_events_mv') }}) != 2

union all

select 'zd_events_mv missing alpha row for expected stage' as failure
where not exists (
    select 1
    from {{ ref('zd_events_mv') }}
    where id = 1
      and payload = '{{ expected_stage }}_mv_alpha'
      and deploy_stage = '{{ expected_stage }}'
)

union all

select 'zd_events_mv still exposes stale rows after swap' as failure
where exists (
    select 1
    from {{ ref('zd_events_mv') }}
    where deploy_stage != '{{ expected_stage }}'
)

union all

select 'zd_chain_middle_mv has unexpected row count' as failure
where (select count(*) from {{ ref('zd_chain_middle_mv') }}) != 2

union all

select 'zd_chain_middle_mv did not apply the expected intermediate definition' as failure
where not exists (
    select 1
    from {{ ref('zd_chain_middle_mv') }}
    where id = 1
      and derived_amount = {% if expected_stage == 'initial' %}100{% else %}1007{% endif %}
      and transform_version = '{{ expected_stage }}'
)

union all

select 'zd_chain_middle_mv still exposes stale intermediate definition rows' as failure
where exists (
    select 1
    from {{ ref('zd_chain_middle_mv') }}
    where transform_version != '{{ expected_stage }}'
)

union all

select 'zd_chain_final_mv has unexpected row count' as failure
where (select count(*) from {{ ref('zd_chain_final_mv') }}) != 2

union all

select 'zd_chain_final_mv did not rebuild against changed intermediate definition' as failure
where not exists (
    select 1
    from {{ ref('zd_chain_final_mv') }}
    where id = 1
      and final_amount = {% if expected_stage == 'initial' %}101{% else %}1008{% endif %}
      and transform_version = '{{ expected_stage }}'
)

union all

select 'zd_chain_final_mv still exposes rows from stale intermediate definition' as failure
where exists (
    select 1
    from {{ ref('zd_chain_final_mv') }}
    where transform_version != '{{ expected_stage }}'
)
