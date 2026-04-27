{{ config(
    materialized='view',
    pre_hook=[
        "create table if not exists {{ target.schema }}.hook_audit (event varchar, model_name varchar)",
        "insert into {{ target.schema }}.hook_audit values ('pre', 'hook_view_model')"
    ],
    post_hook="insert into {{ target.schema }}.hook_audit values ('post', 'hook_view_model')",
    sql_header="insert into " ~ target.schema ~ ".hook_audit values ('sql_header', 'hook_view_model');"
) }}

select 2 as id, 'view' as materialization_kind
