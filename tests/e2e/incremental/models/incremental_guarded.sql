{{ config(materialized='incremental', unique_key='id', on_schema_change='fail') }}

{% set input_relation = incremental_source_relation() %}

-- Adding a column under on_schema_change='fail' makes the incremental run fail
-- after the temp relation is built, which used to leave it behind.
select
    id,
    payload
    {%- if env_var('DBT_RW_INCREMENTAL_GUARD_STAGE', 'stable') == 'changed' %},
    batch_id
    {%- endif %}
from {{ input_relation }}
