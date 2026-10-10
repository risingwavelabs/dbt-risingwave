{{ config(materialized='table') }}

select 1 as id, 10 as v
union all
select 2 as id, 20 as v
