{{ config(materialized='subscription', retention='1D') }}

{{ ref('docs_base_mv') }}
