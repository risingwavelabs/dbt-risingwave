select 'contract_orders must be a table' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'contract_orders'
      and rw_relations.relation_type = 'table'
)

union all

select 'contract_orders row count mismatch' as failure
where (select count(*) from {{ ref('contract_orders') }}) != 2

union all

select 'contract_orders missing alpha row' as failure
where not exists (
    select 1
    from {{ ref('contract_orders') }}
    where id = 1 and payload = 'alpha'
)

union all

select 'contract_orders missing beta row' as failure
where not exists (
    select 1
    from {{ ref('contract_orders') }}
    where id = 2 and payload = 'beta'
)
