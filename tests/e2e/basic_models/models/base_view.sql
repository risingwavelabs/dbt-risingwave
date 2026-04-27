{{ config(materialized='view') }}

select
    id,
    payload || '_view' as payload
from {{ ref('base_table') }}
