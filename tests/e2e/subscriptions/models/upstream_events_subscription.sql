{{ config(
    materialized='subscription',
    retention='1D',
    tags=['upstream']
) }}

{{ ref('subscription_events') }}
