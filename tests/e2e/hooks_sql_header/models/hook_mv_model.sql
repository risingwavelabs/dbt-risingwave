{{ config(
    materialized='materialized_view',
    pre_hook=[
        "create table if not exists {{ target.schema }}.hook_audit (event varchar, model_name varchar)",
        "insert into {{ target.schema }}.hook_audit values ('pre', 'hook_mv_model')"
    ],
    post_hook="insert into {{ target.schema }}.hook_audit values ('post', 'hook_mv_model')",
    sql_header="insert into " ~ target.schema ~ ".hook_audit values ('sql_header', 'hook_mv_model');"
) }}

select 3 as id, 'materialized_view' as materialization_kind
