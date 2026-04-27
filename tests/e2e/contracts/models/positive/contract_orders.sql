{{ config(materialized='table') }}

select
    cast(1 as integer) as id,
    cast('alpha' as varchar) as payload
union all
select
    cast(2 as integer) as id,
    cast('beta' as varchar) as payload
