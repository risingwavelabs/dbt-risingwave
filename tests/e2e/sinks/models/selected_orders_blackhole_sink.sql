{{ config(
    materialized='sink',
    connector='blackhole',
    connector_parameters={
      'type': 'append-only',
      'force_append_only': 'true'
    }
) }}

{{ ref('selected_orders_mv') }}
