{{ config(
    materialized='table',
    tags=['upstream']
) }}

select 1 as id, 'alpha' as payload
union all
select 2 as id, 'beta' as payload
