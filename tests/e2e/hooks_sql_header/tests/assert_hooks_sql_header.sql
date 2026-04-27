with expected as (
    select *
    from (
        values
            ('pre', 'hook_table_model'),
            ('sql_header', 'hook_table_model'),
            ('post', 'hook_table_model'),
            ('pre', 'hook_view_model'),
            ('sql_header', 'hook_view_model'),
            ('post', 'hook_view_model'),
            ('pre', 'hook_mv_model'),
            ('sql_header', 'hook_mv_model'),
            ('post', 'hook_mv_model')
    ) as t(event, model_name)
),
missing_events as (
    select
        'missing hook event: ' || event || ' / ' || model_name as failure
    from expected
    where not exists (
        select 1
        from {{ target.schema }}.hook_audit as hook_audit
        where hook_audit.event = expected.event
          and hook_audit.model_name = expected.model_name
    )
),
missing_created_relations as (
    select 'hook_table_model should be a table' as failure
    where not exists (
        select 1
        from rw_catalog.rw_relations
        join rw_catalog.rw_schemas on schema_id = rw_schemas.id
        where rw_schemas.name = '{{ target.schema }}'
          and rw_relations.name = 'hook_table_model'
          and rw_relations.relation_type = 'table'
    )

    union all

    select 'hook_view_model should be a view' as failure
    where not exists (
        select 1
        from rw_catalog.rw_relations
        join rw_catalog.rw_schemas on schema_id = rw_schemas.id
        where rw_schemas.name = '{{ target.schema }}'
          and rw_relations.name = 'hook_view_model'
          and rw_relations.relation_type = 'view'
    )

    union all

    select 'hook_mv_model should be a materialized view' as failure
    where not exists (
        select 1
        from rw_catalog.rw_relations
        join rw_catalog.rw_schemas on schema_id = rw_schemas.id
        where rw_schemas.name = '{{ target.schema }}'
          and rw_relations.name = 'hook_mv_model'
          and rw_relations.relation_type = 'materialized view'
    )
)
select failure from missing_events
union all
select failure from missing_created_relations
