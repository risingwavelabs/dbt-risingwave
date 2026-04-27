{{ config(materialized='table') }}

select
    cast(1 as integer) as id,
    cast('ok' as varchar) as status
union all
select
    cast(2 as integer) as id,
    cast('bad' as varchar) as status
