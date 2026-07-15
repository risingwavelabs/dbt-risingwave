-- Demonstrates a zero-downtime swap bug with indexed materialized views.
--
-- The index name is derived from the MV identifier (__dbt_index_<mv>_<cols>),
-- which is stable across the swap. After `alter materialized view ... swap`,
-- the pre-existing index stays bound to the *old* MV (now temp-named), so:
--   1. `create index if not exists` on the swapped-in MV is a no-op -> the
--      swapped-in MV ends up with no index (the index is effectively lost).
--   2. the leftover temp MV can't be dropped (the orphaned index is a
--      dependent), so cleanup silently leaves it behind.
--
-- This test encodes the correct behaviour: it PASSES on the initial build and
-- (currently) FAILS after a zero-downtime swap, pinpointing the bug.

{% set events_rel = ref('zd_events_mv') %}
{% set events_index = '__dbt_index_zd_events_mv_id' %}

-- (1) The index must be linked to the swapped-in relation, not lost.
select '{{ events_index }} must be linked to {{ events_rel.identifier }} after the zero-downtime swap' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ events_rel.schema }}'
      and t.relname = '{{ events_rel.identifier }}'
      and i.relname = '{{ events_index }}'
      and ix.indisprimary = false
)

union all

-- (2) The index must not be orphaned on a leftover zero-downtime temp relation.
select '{{ events_index }} is still attached to a leftover zero-downtime temp relation' as failure
where exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ events_rel.schema }}'
      and t.relname like '{{ events_rel.identifier }}%_dbt_zero_down_tmp_%'
      and i.relname = '{{ events_index }}'
)
