{{ config(materialized='materialized_view') }}

select
    id,
    payload || '_mv' as payload
from {{ ref('base_table') }}
