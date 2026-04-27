{% set expected_stage = env_var('DBT_RW_INCREMENTAL_EXPECT_STAGE', 'initial') %}

{% if expected_stage not in ['initial', 'incremental', 'full_refresh'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_INCREMENTAL_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

select 'incremental_events must be a table' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'incremental_events'
      and rw_relations.relation_type = 'table'
)

{% if expected_stage == 'initial' %}

union all

select 'initial incremental_events row count mismatch' as failure
where (select count(*) from {{ ref('incremental_events') }}) != 2

union all

select 'initial incremental_events missing alpha row' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 1 and payload = 'alpha' and batch_id = 1
)

union all

select 'initial incremental_events missing beta row' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 2 and payload = 'beta' and batch_id = 1
)

{% elif expected_stage == 'incremental' %}

union all

select 'incremental incremental_events row count mismatch' as failure
where (select count(*) from {{ ref('incremental_events') }}) != 3

union all

select 'incremental incremental_events missing gamma row' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 3 and payload = 'gamma' and batch_id = 2
)

union all

select 'incremental incremental_events should keep initial rows' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 1 and payload = 'alpha' and batch_id = 1
)

{% elif expected_stage == 'full_refresh' %}

union all

select 'full-refresh incremental_events row count mismatch' as failure
where (select count(*) from {{ ref('incremental_events') }}) != 2

union all

select 'full-refresh incremental_events missing reset_alpha row' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 10 and payload = 'reset_alpha' and batch_id = 3
)

union all

select 'full-refresh incremental_events missing reset_beta row' as failure
where not exists (
    select 1 from {{ ref('incremental_events') }}
    where id = 11 and payload = 'reset_beta' and batch_id = 3
)

union all

select 'full-refresh incremental_events should not keep stale incremental rows' as failure
where exists (
    select 1 from {{ ref('incremental_events') }}
    where id in (1, 2, 3)
)

{% endif %}
