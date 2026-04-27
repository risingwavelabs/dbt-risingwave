{{ config(
    materialized='view',
    persist_docs={'relation': false, 'columns': false}
) }}

select
    id,
    payload || '_view' as payload
from {{ ref('docs_base_table') }}
