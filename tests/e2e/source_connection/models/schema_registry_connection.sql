{{ config(materialized='connection') }}

create connection {{ this.identifier }} with (
    type = 'schema_registry',
    schema.registry = 'http://127.0.0.1:18081'
)
