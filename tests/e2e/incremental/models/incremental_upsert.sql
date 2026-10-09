{{ config(materialized='incremental', unique_key='id') }}

{% set input_relation = incremental_source_relation() %}

select
    id,
    payload,
    batch_id
from {{ input_relation }}
