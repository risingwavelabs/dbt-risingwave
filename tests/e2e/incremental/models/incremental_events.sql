{{ config(materialized='incremental') }}

{% set input_relation = incremental_source_relation() %}

select
    id,
    payload,
    batch_id
from {{ input_relation }}

{% if is_incremental() %}
where id > (select coalesce(max(id), 0) from {{ this }})
{% endif %}
