{{ config(
    materialized='table',
    pre_hook=[
        "create table if not exists {{ target.schema }}.hook_audit (event varchar, model_name varchar)",
        "insert into {{ target.schema }}.hook_audit values ('pre', 'hook_table_model')"
    ],
    post_hook="insert into {{ target.schema }}.hook_audit values ('post', 'hook_table_model')",
    sql_header="insert into " ~ target.schema ~ ".hook_audit values ('sql_header', 'hook_table_model');"
) }}

select 1 as id, 'table' as materialization_kind
