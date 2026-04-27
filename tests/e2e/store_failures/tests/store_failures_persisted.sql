{{
  config(
    store_failures=true,
    store_failures_as='materialized_view',
    alias='store_failures_results'
  )
}}

select
    id,
    status
from {{ ref('store_failures_input') }}
where status = 'bad'
