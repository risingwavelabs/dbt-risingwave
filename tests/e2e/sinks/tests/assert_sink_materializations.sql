select 'sink_source_table must be a table' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'sink_source_table'
      and rw_relations.relation_type = 'table'
)

union all

select 'sink_source_mv must be a materialized view' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'sink_source_mv'
      and rw_relations.relation_type = 'materialized view'
)

union all

select 'managed_blackhole_sink must be a sink' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'managed_blackhole_sink'
      and rw_relations.relation_type = 'sink'
)

union all

select 'raw_blackhole_sink must be a sink' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'raw_blackhole_sink'
      and rw_relations.relation_type = 'sink'
)

union all

select 'replaceable_blackhole_sink must be a sink' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'replaceable_blackhole_sink'
      and rw_relations.relation_type = 'sink'
)

union all

select 'sink_source_mv has unexpected row count' as failure
where (select count(*) from {{ ref('sink_source_mv') }}) != 2

union all

select 'sink_source_mv missing alpha row' as failure
where not exists (
    select 1 from {{ ref('sink_source_mv') }}
    where id = 1 and payload = 'alpha_mv'
)

union all

select 'sink_source_mv missing beta row' as failure
where not exists (
    select 1 from {{ ref('sink_source_mv') }}
    where id = 2 and payload = 'beta_mv'
)

union all

select 'selected_orders_blackhole_sink must sink FROM the selected_orders_mv relation' as failure
where not exists (
    select 1
    from rw_relations
    join rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'selected_orders_blackhole_sink'
      and rw_relations.relation_type = 'sink'
      and rw_relations.definition ilike '%FROM %selected_orders_mv%'
)

union all

select 'escaped_option_blackhole_sink must keep the quoted option and reference the secret' as failure
where not exists (
    select 1
    from rw_sinks
    join rw_schemas on rw_sinks.schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_sinks.name = 'escaped_option_blackhole_sink'
      and rw_sinks.definition like '%e2e.note = ''it''''s quoted''%'
      and rw_sinks.definition like '%e2e.password = secret sink_option_secret%'
)
