select 'datagen_source must be a source' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'datagen_source'
      and rw_relations.relation_type = 'source'
)

union all

select 'schema_registry_connection must exist' as failure
where not exists (
    select 1
    from rw_catalog.rw_connections
    where name = 'schema_registry_connection'
)

union all

select 'schema_registry_connection should be unique' as failure
where (
    select count(*)
    from rw_catalog.rw_connections
    where name = 'schema_registry_connection'
) != 1

union all

select 'api_password_secret must exist' as failure
where not exists (
    select 1
    from rw_catalog.rw_secrets
    join rw_catalog.rw_schemas on rw_secrets.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_secrets.name = 'api_password_secret'
)

union all

select 'api_password_secret should be unique' as failure
where (
    select count(*)
    from rw_catalog.rw_secrets
    join rw_catalog.rw_schemas on rw_secrets.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_secrets.name = 'api_password_secret'
) != 1
