{% set events_rel = ref('zd_events_mv') %}
{% set events_index = '__dbt_index_zd_events_mv_id' %}
{% set preserved_rel = ref('zd_preserved_mv') %}
{% set preserved_index = '__dbt_index_zd_preserved_mv_id' %}

select '{{ events_index }} must be linked to the swapped-in {{ events_rel.identifier }}' as failure
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

select '{{ preserved_index }} must be linked to the swapped-in {{ preserved_rel.identifier }}' as failure
where not exists (
    select 1
    from pg_index ix
    join pg_class i on i.oid = ix.indexrelid
    join pg_class t on t.oid = ix.indrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = '{{ preserved_rel.schema }}'
      and t.relname = '{{ preserved_rel.identifier }}'
      and i.relname = '{{ preserved_index }}'
      and ix.indisprimary = false
)
