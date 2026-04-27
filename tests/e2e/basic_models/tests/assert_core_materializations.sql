select 'base_table must be a table' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'base_table'
      and rw_relations.relation_type = 'table'
)

union all

select 'base_view must be a view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'base_view'
      and rw_relations.relation_type = 'view'
)

union all

select 'events_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'events_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'base_table has unexpected row count' as failure
where (select count(*) from {{ ref('base_table') }}) != 2

union all

select 'base_table missing alpha row' as failure
where not exists (
    select 1 from {{ ref('base_table') }}
    where id = 1 and payload = 'alpha'
)

union all

select 'base_table missing beta row' as failure
where not exists (
    select 1 from {{ ref('base_table') }}
    where id = 2 and payload = 'beta'
)

union all

select 'base_view has unexpected row count' as failure
where (select count(*) from {{ ref('base_view') }}) != 2

union all

select 'base_view missing alpha row' as failure
where not exists (
    select 1 from {{ ref('base_view') }}
    where id = 1 and payload = 'alpha_view'
)

union all

select 'base_view missing beta row' as failure
where not exists (
    select 1 from {{ ref('base_view') }}
    where id = 2 and payload = 'beta_view'
)

union all

select 'events_mv has unexpected row count' as failure
where (select count(*) from {{ ref('events_mv') }}) != 2

union all

select 'events_mv missing alpha row' as failure
where not exists (
    select 1 from {{ ref('events_mv') }}
    where id = 1 and payload = 'alpha_view_mv'
)

union all

select 'events_mv missing beta row' as failure
where not exists (
    select 1 from {{ ref('events_mv') }}
    where id = 2 and payload = 'beta_view_mv'
)
