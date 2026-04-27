{{ config(materialized='table') }}

select 1 as id, 'alpha'::varchar as payload
union all
select 2 as id, 'beta'::varchar as payload
