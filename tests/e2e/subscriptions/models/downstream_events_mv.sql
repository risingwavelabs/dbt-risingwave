{{ config(
    materialized='materialized_view',
    tags=['downstream']
) }}

select count(*) as event_count
from {{ source('upstream', 'subscription_events') }}
