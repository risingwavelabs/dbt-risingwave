{{ config(materialized='secret') }}

create secret {{ this.identifier }}
with (backend = 'meta')
as '{{ env_var("DBT_RW_E2E_SECRET_VALUE", "dbt-risingwave-secret") }}'
