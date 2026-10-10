{{ config(materialized='secret') }}

create secret {{ this.identifier }}
with (backend = 'meta')
as 'dbt-risingwave-sink-secret'
