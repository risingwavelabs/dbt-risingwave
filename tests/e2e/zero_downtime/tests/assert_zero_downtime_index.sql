select '__dbt_index_zd_events_mv_id must be linked to the swapped-in zd_events_mv' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ target.schema }}'
      and t.relname = 'zd_events_mv'
      and i.relname = '__dbt_index_zd_events_mv_id'
      and ix.indisprimary = false
)

union all

select '__dbt_index_zd_deferred_indexed_mv_id must be linked to the swapped-in zd_deferred_indexed_mv' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ target.schema }}'
      and t.relname = 'zd_deferred_indexed_mv'
      and i.relname = '__dbt_index_zd_deferred_indexed_mv_id'
      and ix.indisprimary = false
)
