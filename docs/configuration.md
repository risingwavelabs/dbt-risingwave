# Configuration

This page documents the adapter-specific settings supported by `dbt-risingwave`.

## Profile Configuration

The basic dbt profile looks like this:

```yaml
default:
  outputs:
    dev:
      type: risingwave
      host: 127.0.0.1
      user: root
      pass: ""
      dbname: dev
      port: 4566
      schema: public
  target: dev
```

The adapter also supports several RisingWave session settings directly in the profile. When these are present, `dbt-risingwave` issues the corresponding `SET` statements as soon as the connection opens.

```yaml
default:
  outputs:
    dev:
      type: risingwave
      host: 127.0.0.1
      user: root
      pass: ""
      dbname: dev
      port: 4566
      schema: public
      streaming_parallelism: 2
      streaming_parallelism_for_backfill: 2
      streaming_max_parallelism: 8
      enable_serverless_backfill: true
  target: dev
```

Supported adapter-specific profile keys:

| Key | Description |
| --- | --- |
| `streaming_parallelism` | Sets `SET streaming_parallelism = ...` for the session. |
| `streaming_parallelism_for_backfill` | Sets `SET streaming_parallelism_for_backfill = ...` for the session. |
| `streaming_max_parallelism` | Sets `SET streaming_max_parallelism = ...` for the session. |
| `enable_serverless_backfill` | Sets `SET enable_serverless_backfill = true/false` for the session. |

## Model Configuration

The adapter also supports RisingWave-specific model configs. These can be set in `config(...)` blocks or in `dbt_project.yml`.

### Schema Authorization

Use `schema_authorization` to set the owner of schemas created by dbt:

```sql
{{ config(materialized='table', schema_authorization='my_role') }}

select *
from ...
```

Or globally:

```yaml
models:
  my_project:
    +schema_authorization: my_role
```

Generated SQL:

```sql
create schema if not exists <schema_name> authorization "my_role"
```

### SQL Header

Use `sql_header` to prepend custom SQL before the main statement:

```sql
{{ config(
    materialized='table',
    sql_header='set query_mode = local;'
) }}

select *
from ...
```

The adapter appends its own RisingWave session settings after the custom header when those configs are present.

### Streaming Parallelism Per Model

You can override the session-level streaming settings for an individual model:

```sql
{{ config(
    materialized='materialized_view',
    streaming_parallelism=2,
    streaming_parallelism_for_backfill=2,
    streaming_max_parallelism=8
) }}

select *
from {{ ref('events') }}
```

These values are emitted in the SQL header before the model DDL runs.

### Serverless Backfill

Use `enable_serverless_backfill` to enable serverless backfills for streaming queries on a per-model basis:

```sql
{{ config(
    materialized='materialized_view',
    enable_serverless_backfill=true
) }}

select *
from {{ ref('events') }}
```

Or set it globally in `dbt_project.yml`:

```yaml
models:
  my_project:
    +enable_serverless_backfill: true
```

This emits `set enable_serverless_backfill = true;` before the model DDL runs.

### Background DDL

`dbt-risingwave` supports opting into RisingWave background DDL for these paths:

- `materialized_view`
- `table`
- `sink`
- index creation triggered by model `indexes` config

Enable it per model:

```sql
{{ config(
    materialized='materialized_view',
    background_ddl=true
) }}

select *
from {{ ref('events') }}
```

Or set it in `dbt_project.yml`:

```yaml
models:
  my_project:
    +background_ddl: true
```

How it works:

- The adapter sets `background_ddl = true` before running supported DDL.
- After submitting the DDL, the adapter issues RisingWave `WAIT`.
- dbt does not continue to downstream models, hooks, or tests until `WAIT` returns.

Caveat:

- RisingWave `WAIT` waits for all background creating jobs, not only the job started by the current dbt model. If other background DDL is running in the same cluster, the dbt node may wait on that work too.

### Index Configuration Changes

`materialized_view`, `table`, and `table_with_connector` support dbt's `on_configuration_change` behavior for index changes.

```sql
{{ config(
    materialized='materialized_view',
    indexes=[{'columns': ['user_id']}],
    on_configuration_change='apply'
) }}

select *
from {{ ref('events') }}
```

Supported values:

| Value | Behavior |
| --- | --- |
| `apply` | Apply index configuration changes. |
| `continue` | Keep going and emit a warning. |
| `fail` | Stop the run with an error. |

### Additive Schema Evolution for `table_with_connector`

`table_with_connector` normally runs the model's raw `CREATE TABLE ... WITH (...)` SQL only when the table does not exist, or when dbt is run with `--full-refresh`. If the table already exists, the adapter does not re-run the connector DDL because that can recreate external connector state.

For additive table changes, the adapter supports a conservative `ALTER TABLE ADD COLUMN` path:

```sql
{{ config(
    materialized='table_with_connector',
    on_schema_change='append_new_columns',
    additive_schema_evolution=[
      {'name': 'source_ts', 'data_type': 'timestamp'},
      {'name': 'score', 'data_type': 'double precision', 'default': '0.0'}
    ]
) }}

CREATE TABLE {{ this }} (
    id int,
    payload jsonb,
    source_ts timestamp,
    score double precision
) WITH (
    appendonly = 'true'
);
```

When the table already exists, dbt checks the configured `additive_schema_evolution` columns against RisingWave's catalog and runs one `ALTER TABLE ... ADD COLUMN` statement for each missing column.

Supported values for `on_schema_change` on `table_with_connector`:

| Value | Behavior |
| --- | --- |
| `ignore` | Default. Keep the existing table schema unchanged. |
| `append_new_columns` | Add missing columns listed in `additive_schema_evolution`. |
| `fail` | Fail if any column listed in `additive_schema_evolution` is missing. |
| `sync_all_columns` | Not supported for `table_with_connector`. |

Column entries support:

| Key | Required | Description |
| --- | --- | --- |
| `name` | Yes | Column name. |
| `data_type` | Yes | RisingWave SQL type used in `ALTER TABLE ADD COLUMN`. |
| `default` | No | SQL expression emitted after `DEFAULT`. |
| `not_null` | No | Emits `NOT NULL`. Must be used with `default`. |
| `quote` | No | Quote the column identifier. |

Limitations:

- The adapter does not infer new columns from the raw `CREATE TABLE` SQL. Configure `additive_schema_evolution` explicitly.
- Only additive columns are supported. Primary-key changes, generated columns, column drops, type changes, connector options, watermark clauses, and table properties are not changed.
- Existing downstream materialized views and sinks continue running, but their output schemas do not automatically include newly added columns. Update downstream dbt models separately when they should consume the new column.
- RisingWave does not support this path for webhook tables.

### Zero-Downtime Rebuilds

`materialized_view` and `view` support swap-based zero-downtime rebuilds.

```sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

select *
from {{ ref('events') }}
```

At runtime, enable the behavior with:

```bash
dbt run --vars 'zero_downtime: true'
```

For full details, see [zero-downtime-rebuilds.md](zero-downtime-rebuilds.md).

## Sink Configuration

The `sink` materialization supports two usage patterns.

### Adapter-Managed Sink DDL

Provide connector settings in model config and let the adapter build the `CREATE SINK` statement:

```sql
{{ config(
    materialized='sink',
    connector='kafka',
    connector_parameters={
      'topic': 'orders',
      'properties.bootstrap.server': '127.0.0.1:9092'
    },
    data_format='plain',
    data_encode='json',
    format_parameters={}
) }}

select *
from {{ ref('orders_mv') }}
```

Supported sink-specific configs:

| Key | Required | Description |
| --- | --- | --- |
| `connector` | Yes | Connector name placed in `WITH (...)`. |
| `connector_parameters` | Yes | Connector properties emitted into `WITH (...)`. |
| `data_format` | No | Sink format used in `FORMAT ...`. |
| `data_encode` | No | Sink encoding used in `ENCODE ...`. |
| `format_parameters` | No | Extra format/encode options emitted inside `FORMAT ... ENCODE ... (...)`. |

### Raw SQL Sink DDL

If `connector` is omitted, the adapter runs the SQL in the model as-is. This is useful when you want full control over the sink statement:

```sql
{{ config(materialized='sink') }}

create sink my_sink
from my_mv
with (
  connector = 'blackhole'
)
```

## Related dbt Configs

The adapter also works with standard dbt configs such as `indexes`, `contract`, `grants`, `unique_key`, and `on_schema_change`. Refer to the dbt docs for the generic semantics; this page focuses on RisingWave-specific behavior.
