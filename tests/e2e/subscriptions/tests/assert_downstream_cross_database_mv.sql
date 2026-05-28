{{ config(tags=['downstream']) }}

-- depends_on: {{ ref('downstream_events_mv') }}

select 'downstream cross-database MV should read upstream subscription source rows' as failure
where (select event_count from {{ ref('downstream_events_mv') }}) != 2
