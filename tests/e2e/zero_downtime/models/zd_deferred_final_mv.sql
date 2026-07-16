{{ config(
    alias='zd_deferred_c_mv',
    materialized='materialized_view',
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': false
    }
) }}

select
    id,
    derived_amount + 1 as final_amount,
    deploy_stage
from {{ ref('zd_deferred_middle_mv') }}
