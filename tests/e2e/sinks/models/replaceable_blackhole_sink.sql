{{ config(
    materialized='sink',
    connector='blackhole',
    connector_parameters={
      'type': 'append-only',
      'force_append_only': 'true'
    },
    zero_downtime={'enabled': true}
) }}

{{ ref('sink_source_mv') }}
