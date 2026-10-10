{{ config(materialized='materialized_view') }}

-- Depends on ms_guarded, so switching ms_guarded to a view must be refused.
select id from {{ ref('ms_guarded') }}
