{# The name contains "select" on purpose: sinks must still render `FROM <relation>`. #}
{{ config(materialized='materialized_view') }}

select
    id,
    payload
from {{ ref('sink_source_table') }}
