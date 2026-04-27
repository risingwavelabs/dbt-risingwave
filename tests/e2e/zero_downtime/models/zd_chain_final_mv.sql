{{ config(
    materialized='materialized_view',
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': true
    }
) }}

select
    id,
    derived_amount + 1 as final_amount,
    transform_version
from {{ ref('zd_chain_middle_mv') }}
