{% set expected_stage = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE', 'initial') %}
{% set expect_preserved_temp = env_var('DBT_RW_ZERO_DOWNTIME_EXPECT_INDEX_TEMP', 'false') == 'true' %}
{% set indexed_rel = ref('zd_indexed_mv') %}

{% if expected_stage == 'initial' %}
  {% set expected_indexes = [
      '__dbt_index_zd_indexed_mv_id',
      '__dbt_index_zd_indexed_mv_deploy_stage'
  ] %}
  {% set stale_index = '__dbt_index_zd_indexed_mv_payload' %}
{% elif expected_stage == 'changed' %}
  {% set expected_indexes = [
      '__dbt_index_zd_indexed_mv_id',
      '__dbt_index_zd_indexed_mv_payload'
  ] %}
  {% set stale_index = '__dbt_index_zd_indexed_mv_deploy_stage' %}
{% else %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_EXPECT_STAGE: " ~ expected_stage) }}
{% endif %}

select 'zd_indexed_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_catalog.rw_relations r
    join rw_catalog.rw_schemas s on s.id = r.schema_id
    where s.name = '{{ indexed_rel.schema }}'
      and r.name = '{{ indexed_rel.identifier }}'
      and r.relation_type = 'materialized view'
)

{% for expected_index in expected_indexes %}
union all

select '{{ expected_index }} must be attached to zd_indexed_mv' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname = '{{ indexed_rel.identifier }}'
      and i.relname = '{{ expected_index }}'
      and ix.indisprimary = false
)

union all

select '{{ expected_index }} must not remain attached to a temp MV' as failure
where exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname like '{{ indexed_rel.identifier }}_dbt_zero_down_tmp_%'
      and i.relname = '{{ expected_index }}'
      and ix.indisprimary = false
)
{% endfor %}

union all

select 'zd_indexed_mv must have exactly two active indexes' as failure
where (
    select count(*)
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname = '{{ indexed_rel.identifier }}'
      and ix.indisprimary = false
) != 2

union all

select 'staged index names must be promoted after the MV swap' as failure
where exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname = '{{ indexed_rel.identifier }}'
      and i.relname like '__dbt_index_%_dbt_zero_down_tmp_%'
      and ix.indisprimary = false
)

union all

select 'the pre-swap MV and its indexes must remain available before cleanup' as failure
where {{ 'true' if expect_preserved_temp else 'false' }}
  and not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname like '{{ indexed_rel.identifier }}_dbt_zero_down_tmp_%'
      and i.relname = '__dbt_index_zd_indexed_mv_deploy_stage'
      and ix.indisprimary = false
)

union all

select 'the replaced id index must be retained under a retired name before cleanup' as failure
where {{ 'true' if expect_preserved_temp else 'false' }}
  and not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    join pg_attribute a
      on a.attrelid = t.oid
     and a.attnum = any(ix.indkey)
     and array_position(ix.indkey, a.attnum) <= ix.indnkeyatts
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname like '{{ indexed_rel.identifier }}_dbt_zero_down_tmp_%'
      and i.relname != '__dbt_index_zd_indexed_mv_id'
      and a.attname = 'id'
      and ix.indisprimary = false
)

union all

select 'the indexed temp MV must be removed by cleanup_temp_objects' as failure
where {{ 'false' if expect_preserved_temp else 'true' }}
  and exists (
    select 1
    from rw_catalog.rw_relations r
    join rw_catalog.rw_schemas s on s.id = r.schema_id
    where s.name = '{{ indexed_rel.schema }}'
      and r.name like '{{ indexed_rel.identifier }}_dbt_zero_down_tmp_%'
  )

union all

select '{{ stale_index }} must be removed after cleanup' as failure
where {{ 'false' if expect_preserved_temp else 'true' }}
  and exists (
    select 1
    from pg_class i
    join pg_namespace n on n.oid = i.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and i.relname = '{{ stale_index }}'
  )
