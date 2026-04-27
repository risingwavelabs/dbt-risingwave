{{ config(materialized='table') }}

select
    id,
    name_upper
from {{ ref('ephemeral_active_users') }}
order by id
