{{ config(
    materialized='sink',
    connector='blackhole',
    connector_parameters={
      'type': 'append-only',
      'force_append_only': 'true'
    }
) }}

select
    id,
    payload
from {{ ref('sink_source_mv') }}
