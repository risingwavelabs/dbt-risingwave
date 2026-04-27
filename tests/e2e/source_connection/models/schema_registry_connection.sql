{{ config(materialized='connection') }}

create connection {{ this.identifier }} with (
    type = 'schema_registry',
    schema.registry = '{{ env_var("DBT_RW_SCHEMA_REGISTRY_URL", "http://127.0.0.1:18081") }}'
)
