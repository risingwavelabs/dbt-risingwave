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

### Background DDL

`background_ddl=true` lets supported materializations submit background DDL while still preserving dbt semantics by issuing RisingWave `WAIT` before dbt continues.

See [docs/configuration.md](docs/configuration.md) for supported materializations, examples, and the cluster-wide `WAIT` caveat.

### Zero-Downtime Rebuilds

`materialized_view` and `view` support swap-based zero-downtime rebuilds through `zero_downtime={'enabled': true}` plus the runtime flag `--vars 'zero_downtime: true'`.

See [docs/zero-downtime-rebuilds.md](docs/zero-downtime-rebuilds.md) for requirements, cleanup behavior, and helper commands.

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
| `source` | Runs a full `CREATE SOURCE` statement supplied by the model SQL. |
| `table_with_connector` | Runs a full `CREATE TABLE ... WITH (...)` statement supplied by the model SQL. |
| `sink` | Creates a sink, either from adapter configs or from a full SQL statement. |

See [docs/configuration.md](docs/configuration.md) for adapter-specific configuration examples, including streaming session settings and background DDL.

## Documentation

- [docs/README.md](docs/README.md): documentation index
- [docs/configuration.md](docs/configuration.md): profile options, model configs, sink settings, and background DDL usage
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
