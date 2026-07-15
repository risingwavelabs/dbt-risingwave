{% set stage = env_var('DBT_RW_ZERO_DOWNTIME_STAGE', 'initial') %}

{% if stage not in ['initial', 'changed'] %}
  {{ exceptions.raise_compiler_error("Invalid DBT_RW_ZERO_DOWNTIME_STAGE: " ~ stage) }}
{% endif %}

{# Dedicated indexed model for the zero-downtime index test. Kept separate from
   the models the materializations test scans, because RisingWave crashes on a
   `not exists (... where <index_key> and <non_indexed_col>)` scan of a
   covering-indexed MV (a RisingWave engine bug), and that test uses that shape.
   The index test only inspects pg_index for this relation, so it never triggers
   the crash. #}
{{ config(
    materialized='materialized_view',
    indexes=[{'columns': ['id'], 'include': ['payload']}],
    background_ddl=true,
    zero_downtime={
      'enabled': true,
      'immediate_cleanup': true
    }
) }}

select
    cast(1 as int) as id,
    cast('{{ stage }}_indexed_alpha' as varchar) as payload
union all
select
    cast(2 as int) as id,
    cast('{{ stage }}_indexed_beta' as varchar) as payload
