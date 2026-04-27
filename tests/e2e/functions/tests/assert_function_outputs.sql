select 'expected SQL scalar function to be registered' as failure
where not exists (
    select 1
    from rw_catalog.rw_functions
    where name = 'double_price'
)

union all

select 'expected JavaScript scalar function to be registered' as failure
where not exists (
    select 1
    from rw_catalog.rw_functions
    where name = 'double_price_js'
)

union all

select 'expected external Python scalar function to be registered' as failure
where not exists (
    select 1
    from rw_catalog.rw_functions
    where name = 'double_price_py'
)

union all

select 'expected async JavaScript HTTP function to be registered' as failure
where not exists (
    select 1
    from rw_catalog.rw_functions
    where name = 'http_post_echo_js'
)

union all

select 'function_outputs should contain two rows' as failure
where (select count(*) from {{ ref('function_outputs') }}) != 2

union all

select 'SQL function returned unexpected result' as failure
where exists (
    select 1
    from {{ ref('function_outputs') }}
    where sql_price != price * 2
)

union all

select 'JavaScript function returned unexpected result' as failure
where exists (
    select 1
    from {{ ref('function_outputs') }}
    where js_price != price * 2
)

union all

select 'external Python function returned unexpected result' as failure
where exists (
    select 1
    from {{ ref('function_outputs') }}
    where py_price != price * 2
)

union all

select 'async JavaScript HTTP function returned unexpected result' as failure
where exists (
    select 1
    from {{ ref('function_outputs') }}
    where echoed_value != 'dbt:risingwave'
)
