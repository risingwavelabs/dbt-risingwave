{% set stage = env_var('DBT_RW_MATERIALIZATION_SWITCH_STAGE', 'initial') %}
{{ config(materialized=('table' if stage == 'initial' else 'materialized_view'), indexes=[{'columns': ['v']}]) }}

select id, v from {{ ref('ms_base') }}
