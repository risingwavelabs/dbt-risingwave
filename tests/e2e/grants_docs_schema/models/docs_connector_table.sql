{{ config(materialized='table_with_connector') }}

create table {{ this }} (
    id int,
    payload varchar
) with (
    appendonly = 'true'
)
