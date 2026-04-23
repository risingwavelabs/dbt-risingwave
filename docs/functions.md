# Functions

`dbt-risingwave` supports the upstream dbt `function` resource for a constrained first version of RisingWave UDF support.

## Scope

This first version supports:

- SQL scalar functions
- JavaScript scalar functions through `config.language: javascript`
- external Python scalar functions through `config.language: python`
  - with `config.link: http://host:port`
  - optional `config.remote_name`
  - optional `config.always_retry_on_network_error`
- JavaScript async options through adapter config:
  - `async`
  - `batch`
  - `always_retry_on_network_error`
- function creation from dbt `functions/` resources
- function references from models through `{{ function('name') }}(...)`
- function volatility config:
  - `deterministic` -> `IMMUTABLE`
  - `stable` -> `STABLE`
  - `non-deterministic` -> `VOLATILE`

## Example

### SQL Scalar Function

Project layout:

```text
functions/
  price_for_xlarge.sql
  price_for_xlarge.yml
models/
  udf_example.sql
```

Function SQL:

```sql
select price * 2
```

Function YAML:

```yaml
functions:
  - name: price_for_xlarge
    description: Double the price
    arguments:
      - name: price
        data_type: float
    returns:
      data_type: float
```

Model usage:

```sql
{{ config(materialized='view') }}

select {{ function('price_for_xlarge') }}(100::float8) as xlarge_price
```

### JavaScript Scalar Function

Project layout:

```text
functions/
  price_for_xlarge_js.sql
  price_for_xlarge_js.yml
models/
  js_udf_example.sql
```

Function file:

```sql
export function price_for_xlarge_js(price) {
    return price * 2;
}
```

Function YAML:

```yaml
functions:
  - name: price_for_xlarge_js
    config:
      language: javascript
    arguments:
      - name: price
        data_type: float8
    returns:
      data_type: float8
```

Model usage:

```sql
{{ config(materialized='view') }}

select {{ function('price_for_xlarge_js') }}(100::float8) as xlarge_price
```

### Python Scalar Function

Project layout:

```text
functions/
  price_for_xlarge_py.sql
  price_for_xlarge_py.yml
models/
  py_udf_example.sql
```

Function file:

```sql
-- The adapter ignores the body for external Python UDFs.
-- The real implementation lives in the external UDF server.
```

Function YAML:

```yaml
functions:
  - name: price_for_xlarge_py
    config:
      language: python
      link: http://127.0.0.1:8815
    arguments:
      - name: price
        data_type: float8
    returns:
      data_type: float8
```

Model usage:

```sql
{{ config(materialized='view') }}

select {{ function('price_for_xlarge_py') }}(100::float8) as xlarge_price
```

## First-Version Contract

This adapter currently materializes SQL scalar functions with:

```sql
CREATE FUNCTION IF NOT EXISTS ...
```

That contract has two important consequences:

1. dbt can create and reference the function.
2. dbt does not replace or update an existing RisingWave function body.

If the function definition changes, drop the function first or deploy it under a new name.

For JavaScript, the function body is emitted as:

```sql
CREATE FUNCTION IF NOT EXISTS ... LANGUAGE JAVASCRIPT AS $$ ... $$;
```

The exported JavaScript function should match the dbt function name.

This uses an adapter-level workaround for current dbt-core limits. Upstream dbt function parsing currently only accepts `.sql` and `.py` files, so JavaScript UDFs are authored in `functions/*.sql` and switched to JavaScript with `config.language: javascript`.

For external Python, `dbt-core`'s native `python` function contract still expects fields such as `runtime_version` and `entry_point`, but RisingWave external Python UDFs use `AS 'remote_name' USING LINK 'http://host:port'`. So this adapter authors external Python UDFs in `functions/*.sql` with `config.language: python` and adapter-specific config.

Current Python-specific contract:

- set `config.language: python`
- set `config.link`
- optional `config.remote_name`; defaults to the dbt function name
- optional `config.always_retry_on_network_error`
- you do not need to set `runtime_version` or `entry_point`; the adapter fills placeholders for dbt-core validation

Python UDFs are materialized as:

```sql
CREATE FUNCTION IF NOT EXISTS ... AS 'remote_name' USING LINK 'http://host:port';
```

### JavaScript Async Options

For embedded JavaScript scalar UDFs, the adapter also maps these function configs into RisingWave `WITH (...)` options:

```yaml
functions:
  - name: http_get_todo_name_js
    config:
      language: javascript
      async: true
      batch: false
      always_retry_on_network_error: false
```

Current mapping:

- `config.async: true` -> `WITH (async = true)`
- `config.batch: true` -> `WITH (batch = true)`
- `config.always_retry_on_network_error: true` -> `WITH (always_retry_on_network_error = true)`

This is enough to support real async `fetch(...)` use cases such as HTTP GET and POST.

## Current Limitations

This first version does not support:

- `CREATE OR REPLACE FUNCTION`
- updating an existing function body through dbt
- overload-family management
- aggregate functions
- table functions
- default arguments
- native `.js` function resources in dbt-core
- native `.py` function resources for RisingWave external Python UDFs

## Cluster Requirement

JavaScript UDF creation depends on RisingWave having embedded JavaScript UDF support enabled. If the cluster disables `enable_embedded_javascript_udf`, dbt function creation will fail at execution time.

External Python UDF creation requires the configured UDF server link to be reachable from RisingWave. If the UDF server is down or unreachable, function creation or execution will fail at runtime.

The overload limitation is especially important. The adapter only treats a function name as a manageable dbt relation when that name maps to a single signature inside the schema.

## Validation Example

The live example and singular tests for this first version live in the companion project:

- `dbt_rw_nexmark`

See its function example for a runnable RisingWave validation flow.
