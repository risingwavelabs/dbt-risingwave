{% set stage = env_var('DBT_RW_MATERIALIZATION_SWITCH_STAGE', 'initial') %}
{{ config(materialized=('view' if stage == 'initial' else 'materialized_view')) }}

select id, v from {{ ref('ms_base') }}
