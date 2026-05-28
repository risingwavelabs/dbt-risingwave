{{ config(tags=['upstream']) }}

-- depends_on: {{ ref('upstream_events_subscription') }}

select 'upstream_events_subscription must be a subscription' as failure
where not exists (
    select 1
    from rw_catalog.rw_relations
    join rw_catalog.rw_schemas on schema_id = rw_schemas.id
    where rw_schemas.name = '{{ target.schema }}'
      and rw_relations.name = 'upstream_events_subscription'
      and rw_relations.relation_type = 'subscription'
)
