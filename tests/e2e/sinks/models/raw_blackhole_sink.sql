{{ config(materialized='sink') }}

create sink {{ this }}
as select
    id,
    payload
from {{ ref('sink_source_mv') }}
with (
    connector = 'blackhole',
    type = 'append-only',
    force_append_only = 'true'
);
