with target_schema as (
    select
        rw_schemas.id,
        rw_schemas.name,
        rw_users.name as owner_name
    from rw_catalog.rw_schemas
    join rw_catalog.rw_users on rw_schemas.owner = rw_users.id
    where rw_schemas.name = '{{ target.schema }}'
),
target_relations as (
    select
        rw_relations.id,
        rw_relations.name,
        rw_relations.relation_type,
        rw_relations.acl
    from rw_catalog.rw_relations
    join target_schema on rw_relations.schema_id = target_schema.id
    where rw_relations.name in ('docs_base_table', 'docs_base_view', 'docs_base_mv')
),
relation_comments as (
    select
        target_relations.name,
        rw_description.description
    from target_relations
    join rw_catalog.rw_description
      on rw_description.objoid = target_relations.id
     and rw_description.objsubid is null
),
column_comments as (
    select
        target_relations.name as relation_name,
        rw_columns.name as column_name,
        rw_description.description
    from target_relations
    join rw_catalog.rw_columns
      on rw_columns.relation_id = target_relations.id
    left join rw_catalog.rw_description
      on rw_description.objoid = target_relations.id
     and rw_description.objsubid = rw_columns.position
)
select 'target schema owner mismatch' as failure
where not exists (
    select 1
    from target_schema
    where owner_name = 'dbt_e2e_gds_owner'
)

union all

select 'docs_base_table must be a table' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_table'
      and relation_type = 'table'
)

union all

select 'docs_base_view must be a view' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_view'
      and relation_type = 'view'
)

union all

select 'docs_base_mv must be a materialized view' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_mv'
      and relation_type = 'materialized view'
)

union all

select 'docs_base_table grant missing' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_table'
      and array_to_string(acl, ',') like '%dbt_e2e_gds_grantee=r/%'
)

union all

select 'docs_base_view grant missing' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_view'
      and array_to_string(acl, ',') like '%dbt_e2e_gds_grantee=r/%'
)

union all

select 'docs_base_mv grant missing' as failure
where not exists (
    select 1
    from target_relations
    where name = 'docs_base_mv'
      and array_to_string(acl, ',') like '%dbt_e2e_gds_grantee=r/%'
)

union all

select 'docs_base_table relation comment mismatch' as failure
where not exists (
    select 1
    from relation_comments
    where name = 'docs_base_table'
      and description = 'Table relation comment from persist_docs.'
)

union all

select 'docs_base_table id comment mismatch' as failure
where not exists (
    select 1
    from column_comments
    where relation_name = 'docs_base_table'
      and column_name = 'id'
      and description = 'Table id column comment from persist_docs.'
)
