{{ config(
    materialized='materialized_view',
    background_ddl=true
) }}

select
    cast(1 as int) as id,
    cast(10 as int) as amount
union all
select
    cast(2 as int) as id,
    cast(20 as int) as amount
