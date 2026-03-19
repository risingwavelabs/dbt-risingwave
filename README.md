# dbt-risingwave

A [RisingWave](https://github.com/risingwavelabs/risingwave) adapter plugin for [dbt](https://www.getdbt.com/).

RisingWave is a cloud-native streaming database that uses SQL as the interface language. It is designed to reduce the complexity and cost of building real-time applications. See <https://www.risingwave.com>.

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

## Materializations

The adapter follows standard dbt model workflows, with RisingWave-specific materializations and behaviors.

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

```sh
dbt run --select "my_model+"
dbt run --select "+my_model"
dbt run --select "+my_model+"
```

## Examples

- Official dbt example: [jaffle_shop](https://github.com/dbt-labs/jaffle_shop)
- RisingWave example: [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark)
