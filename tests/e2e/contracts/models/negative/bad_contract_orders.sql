{{ config(materialized='table', tags=['contract_negative']) }}

select
    cast(1 as integer) as id,
    cast('not_an_integer' as varchar) as payload
