-- Verifies index handling across a zero-downtime swap of an indexed MV.
--
-- The index name is derived from the MV identifier (__dbt_index_<mv>_<cols>),
-- which is stable across the swap. `alter materialized view ... swap` renames
-- the MVs but the index follows its old MV by OID, so without special handling:
--   1. `create index if not exists` on the swapped-in MV is a no-op (the name
--      is still taken) -> the swapped-in MV ends up with no index, and
--   2. the leftover temp MV can't be dropped (the orphaned index is a
--      dependent), so cleanup silently leaves it behind.
-- The materialization drops the stale index off the old MV right after the
-- swap, which fixes both. This test asserts that outcome: it passes on the
-- initial build and after the swap.

{% set indexed_rel = ref('zd_indexed_mv') %}
{% set indexed_index = '__dbt_index_zd_indexed_mv_id' %}

-- (1) The index must be linked to the swapped-in relation, not lost.
select '{{ indexed_index }} must be linked to {{ indexed_rel.identifier }} after the zero-downtime swap' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname = '{{ indexed_rel.identifier }}'
      and i.relname = '{{ indexed_index }}'
      and ix.indisprimary = false
)

union all

-- (2) The index must not be orphaned on a leftover zero-downtime temp relation.
select '{{ indexed_index }} is still attached to a leftover zero-downtime temp relation' as failure
where exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ indexed_rel.schema }}'
      and t.relname like '{{ indexed_rel.identifier }}%_dbt_zero_down_tmp_%'
      and i.relname = '{{ indexed_index }}'
)
