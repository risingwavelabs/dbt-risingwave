-- After a zero-downtime swap the index must stay on the swapped-in MV and never
-- be orphaned on a leftover temp relation.

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
