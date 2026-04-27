{% set expected_stage = env_var('DBT_RW_INDEX_EXPECT_STAGE', 'initial') %}

{% if expected_stage == 'initial' %}
  {% set expected_index = '__dbt_index_indexed_events_mv_user_id' %}
  {% set stale_index = '__dbt_index_indexed_events_mv_event_type' %}
{% elif expected_stage == 'changed' %}
  {% set expected_index = '__dbt_index_indexed_events_mv_event_type' %}
  {% set stale_index = '__dbt_index_indexed_events_mv_user_id' %}
{% else %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_INDEX_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

select 'indexed_events_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'indexed_events_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'indexed_events_mv has unexpected row count' as failure
where (select count(*) from {{ ref('indexed_events_mv') }}) != 2

union all

select '{{ expected_index }} must exist' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ target.schema }}'
      and t.relname = 'indexed_events_mv'
      and i.relname = '{{ expected_index }}'
      and ix.indisprimary = false
)

union all

select '{{ stale_index }} should not exist' as failure
where exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ target.schema }}'
      and t.relname = 'indexed_events_mv'
      and i.relname = '{{ stale_index }}'
      and ix.indisprimary = false
)
