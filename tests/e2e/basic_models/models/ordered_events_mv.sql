{% set edge_schema = adapter.quote(this.schema) %}

{{ config(
    materialized='materialized_view',
    backfill_order=[
        edge_schema ~ '."base_table" -> ' ~ edge_schema ~ '."backfill_dimension"'
    ]
) }}

select
    events.id,
    events.payload,
    dimensions.category
from {{ ref('base_table') }} as events
join {{ ref('backfill_dimension') }} as dimensions using (id)
