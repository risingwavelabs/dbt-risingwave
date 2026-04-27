{{ config(materialized='ephemeral') }}

select
    id,
    name,
    status,
    upper(name) as name_upper
from {{ ref('seed_users') }}
where status = 'active'
