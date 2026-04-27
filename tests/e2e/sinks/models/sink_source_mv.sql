{{ config(materialized='materialized_view') }}

select
    id,
    payload || '_mv' as payload
from {{ ref('sink_source_table') }}
