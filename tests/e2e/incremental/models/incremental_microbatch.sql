{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='event_ts',
    batch_size='day',
    lookback=2,
    begin=(modules.datetime.datetime.now(modules.pytz.utc) - modules.datetime.timedelta(days=7)).strftime('%Y-%m-%d')
) }}

select
    id,
    payload,
    event_ts
from {{ source('incremental_e2e', 'microbatch_input') }}
