{{ config(materialized='view') }}

with input_prices(price) as (
    values
        (10.0::float8),
        (12.5::float8)
),
payloads(prefix, value) as (
    values
        ('dbt', 'risingwave')
)
select
    price,
    {{ function('double_price') }}(price) as sql_price,
    {{ function('double_price_js') }}(price) as js_price,
    {{ function('double_price_py') }}(price) as py_price,
    {{ function('http_post_echo_js') }}(payloads.prefix, payloads.value) as echoed_value
from input_prices
cross join payloads
