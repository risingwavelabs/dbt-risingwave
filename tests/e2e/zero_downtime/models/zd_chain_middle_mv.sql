{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

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
    {% if stage == 'initial' %}
    amount * 10
    {% else %}
    amount * 100 + 7
    {% endif %} as derived_amount,
    cast('{{ stage }}' as varchar) as transform_version
from {{ ref('zd_chain_source_mv') }}
