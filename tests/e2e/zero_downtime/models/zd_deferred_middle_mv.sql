{{ config(
    alias='zd_deferred_b_mv',
    materialized='materialized_view',
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': false
    }
) }}

select
    id,
    amount * 2 as derived_amount,
    deploy_stage
from {{ ref('zd_deferred_source_mv') }}
