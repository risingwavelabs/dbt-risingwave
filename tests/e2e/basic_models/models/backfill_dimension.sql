{{ config(materialized='table') }}

select 1 as id, 'first'::varchar as category
union all
select 2 as id, 'second'::varchar as category
