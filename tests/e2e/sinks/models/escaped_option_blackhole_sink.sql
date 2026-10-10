{{ config(
    materialized='sink',
    connector='blackhole',
    connector_parameters={
      'type': 'append-only',
      'force_append_only': 'true',
      'e2e.note': "it's quoted",
      'e2e.password': {'secret': 'sink_option_secret'}
    }
) }}

-- depends_on: {{ ref('sink_option_secret') }}

select
    id,
    payload
from {{ ref('sink_source_mv') }}
