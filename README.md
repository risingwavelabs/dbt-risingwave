# dbt-risingwave

A [RisingWave](https://github.com/risingwavelabs/risingwave) adapter plugin for [dbt](https://www.getdbt.com/).

RisingWave is a cloud-native streaming database that uses SQL as the interface language. It is designed to reduce the complexity and cost of building real-time applications. See <https://www.risingwave.com>.

dbt enables data analysts and engineers to transform data using software engineering workflows. For the broader RisingWave integration guide, see <https://docs.risingwave.com/integrations/other/dbt>.

## Getting Started

1. Install `dbt-risingwave`.

```shell
python3 -m pip install dbt-risingwave
```

2. Get RisingWave running by following the official guide: <https://www.risingwave.dev/docs/current/get-started/>.

3. Configure `~/.dbt/profiles.yml`.

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

4. Run `dbt debug` to verify the connection.

## Common Features

Detailed reference: [`docs/`](docs/README.md).

### Schema Authorization

Use `schema_authorization` when dbt should create schemas with a specific owner:

```sql
{{ config(materialized='table', schema_authorization='my_role') }}
```

See [docs/configuration.md](docs/configuration.md) for model-level and `dbt_project.yml` examples.

### Streaming Parallelism

The adapter supports RisingWave session settings such as `streaming_parallelism`, `streaming_parallelism_for_backfill`, and `streaming_max_parallelism` in both profiles and model configs.

See [docs/configuration.md](docs/configuration.md) for the full configuration matrix.

### Serverless Backfill

Use `enable_serverless_backfill=true` in a model config or profile to enable serverless backfills for streaming queries.

See [docs/configuration.md](docs/configuration.md) for examples.

### Background DDL

`background_ddl=true` lets supported materializations submit background DDL while still preserving dbt semantics by issuing RisingWave `WAIT` before dbt continues.

See [docs/configuration.md](docs/configuration.md) for supported materializations, examples, and the cluster-wide `WAIT` caveat.

### Zero-Downtime Rebuilds

`materialized_view` and `view` support swap-based zero-downtime rebuilds through `zero_downtime={'enabled': true}` plus the runtime flag `--vars 'zero_downtime: true'`.

See [docs/zero-downtime-rebuilds.md](docs/zero-downtime-rebuilds.md) for requirements, cleanup behavior, and helper commands.

### Functions

`dbt-risingwave` now supports a first version of dbt `function` resources for RisingWave scalar UDFs.

Current contract:

- supported:
  - SQL scalar functions
  - JavaScript scalar functions via `functions/*.sql` plus `config.language: javascript`
  - external Python scalar functions via `functions/*.sql` plus `config.language: python`
    - with `config.link: http://host:port`
    - optional `config.remote_name`
    - optional `config.always_retry_on_network_error`
- materialization: `CREATE FUNCTION IF NOT EXISTS`
- JavaScript async options:
  - `config.async: true` -> `WITH (async = true)`
  - `config.batch: true` -> `WITH (batch = true)`
  - `config.always_retry_on_network_error: true` -> `WITH (always_retry_on_network_error = true)`
- supported volatility config:
  - `deterministic` -> `IMMUTABLE`
  - `stable` -> `STABLE`
  - `non-deterministic` -> `VOLATILE`

Current limits:

- no replace/update path for an existing function body
- no overload-family management
- no aggregate or table functions
- no default arguments
- upstream dbt-core function contracts do not yet map cleanly to RisingWave-native `.js` authoring or RisingWave external Python UDF authoring, so JavaScript and Python currently use adapter config on `functions/*.sql`

See [docs/functions.md](docs/functions.md) for the full first-version contract and example layout.

### Indexes

RisingWave indexes support `INCLUDE` and `DISTRIBUTED BY` clauses beyond what the Postgres adapter exposes. Configure them in the model config:

```sql
{{ config(
    materialized='materialized_view',
    indexes=[
        {'columns': ['user_id'], 'include': ['name', 'email'], 'distributed_by': ['user_id']}
    ]
) }}
```

This generates:

```sql
CREATE INDEX IF NOT EXISTS "__dbt_index_mv_user_id"
  ON mv (user_id)
  INCLUDE (name, email)
  DISTRIBUTED BY (user_id);
```

| Option | Description |
| --- | --- |
| `columns` | Key columns for the index (required). |
| `include` | Additional columns stored in the index but not part of the key (optional). |
| `distributed_by` | Columns used to distribute the index across nodes (optional). |

Note: RisingWave does not support `unique` or `type` (index method) options from the Postgres adapter. These options are silently ignored.

## Materializations

The adapter follows standard dbt model workflows, with RisingWave-specific materializations and behaviors.

Typical usage:

```sql
{{ config(materialized='materialized_view') }}

select *
from {{ ref('events') }}
```

| Materialization | Notes |
| --- | --- |
| `materialized_view` | Creates a materialized view. This is the main streaming materialization for RisingWave. |
| `materializedview` | Deprecated. Kept only for backward compatibility. Use `materialized_view` instead. |
| `ephemeral` | Uses common table expressions under the hood. |
| `table` | Creates a table from the model query. |
| `view` | Creates a view from the model query. |
| `incremental` | Batch-style incremental updates for tables. Prefer `materialized_view` when a streaming MV fits the workload. |
| `connection` | Runs a full `CREATE CONNECTION` statement supplied by the model SQL. |
| `source` | Runs a full `CREATE SOURCE` statement supplied by the model SQL. |
| `table_with_connector` | Runs a full `CREATE TABLE ... WITH (...)` statement supplied by the model SQL. Supports explicit additive `ALTER TABLE ADD COLUMN` changes through `on_schema_change='append_new_columns'`. |
| `sink` | Creates a sink, either from adapter configs or from a full SQL statement. |

See [docs/configuration.md](docs/configuration.md) for adapter-specific configuration examples, including streaming session settings and background DDL.

## Documentation

- [docs/README.md](docs/README.md): documentation index
- [docs/configuration.md](docs/configuration.md): profile options, model configs, sink settings, and background DDL usage
- [docs/functions.md](docs/functions.md): first-version RisingWave scalar function support and limitations
- [docs/zero-downtime-rebuilds.md](docs/zero-downtime-rebuilds.md): zero-downtime rebuild behavior for materialized views and views

## dbt Run Behavior

- `dbt run`: creates models that do not already exist.
- `dbt run --full-refresh`: drops and recreates models so the deployed objects match the current dbt definitions.

## Graph Operators

[Graph operators](https://docs.getdbt.com/reference/node-selection/graph-operators) are useful when you want to rebuild only part of a project.

## Data Tests

`dbt-risingwave` extends dbt data-test failure storage to support `materialized_view` in addition to the upstream `table` and `view` options.

Example:

```yaml
models:
  - name: my_model
    columns:
      - name: id
        tests:
          - not_null:
              config:
                store_failures: true
                store_failures_as: materialized_view
```

This is useful for realtime monitoring workflows where test failures should remain continuously queryable as a RisingWave materialized view.

```sh
dbt run --select "my_model+"   # select my_model and all children
dbt run --select "+my_model"   # select my_model and all parents
dbt run --select "+my_model+"  # select my_model, and all of its parents and children
```

## Examples

- Official dbt example: [jaffle_shop](https://github.com/dbt-labs/jaffle_shop)
- RisingWave example: [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark)
