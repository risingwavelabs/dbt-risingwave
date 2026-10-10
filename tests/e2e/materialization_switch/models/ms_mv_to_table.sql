{% set stage = env_var('DBT_RW_MATERIALIZATION_SWITCH_STAGE', 'initial') %}
{{ config(materialized=('materialized_view' if stage == 'initial' else 'table')) }}

select id, v from {{ ref('ms_base') }}
