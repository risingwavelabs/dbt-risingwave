{% set expect_extra_columns = env_var('DBT_RW_TWC_EXPECT_EXTRA', 'false') == 'true' %}

select 'connector_events must be a table' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'connector_events'
      and rw_relations.relation_type = 'table'
)

union all

select 'connector_events missing id column' as failure
where not exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'id'
)

union all

select 'connector_events missing payload column' as failure
where not exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'payload'
)

{% if expect_extra_columns %}

union all

select 'connector_events should preserve rows created before additive schema evolution' as failure
where not exists (
    select 1
    from {{ ref('connector_events') }}
    where id = 101
      and payload = 'before_add_column'
)

union all

select 'connector_events missing source_tag column after additive schema evolution' as failure
where not exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'source_tag'
)

union all

select 'connector_events missing score column after additive schema evolution' as failure
where not exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'score'
)

union all

select 'connector_events preserved row should expose NULL source_tag after add column' as failure
where not exists (
    select 1
    from {{ ref('connector_events') }}
    where id = 101
      and payload = 'before_add_column'
      and source_tag is null
)

union all

select 'connector_events preserved row should expose NULL score after add column' as failure
where not exists (
    select 1
    from {{ ref('connector_events') }}
    where id = 101
      and payload = 'before_add_column'
      and score is null
)

union all

select 'connector_events has unexpected column count after additive schema evolution' as failure
where (
    select count(*)
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
) != 4

{% else %}

union all

select 'connector_events should not have source_tag before additive schema evolution' as failure
where exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'source_tag'
)

union all

select 'connector_events should not have score before additive schema evolution' as failure
where exists (
    select 1
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
      and column_name = 'score'
)

union all

select 'connector_events has unexpected column count before additive schema evolution' as failure
where (
    select count(*)
    from information_schema.columns
    where table_schema = '{{ target.schema }}'
      and table_name = 'connector_events'
) != 2

{% endif %}
