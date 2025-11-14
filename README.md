# dbt-risingwave

A [RisingWave](https://github.com/risingwavelabs/risingwave) 
adapter plugin for [dbt](https://www.getdbt.com/).

**RisingWave** is a cloud-native streaming database that uses SQL as the interface language. It is designed to reduce the complexity and cost of building real-time applications. https://www.risingwave.com

**dbt** enables data analysts and engineers to transform their data using the same practices that software engineers use to build applications. [Use dbt for data transformations in RisingWave](https://docs.risingwave.com/docs/current/use-dbt/)

## Getting started

The package has not been published to PyPI, please install it via git.

1. Install `dbt-risingwave`

``` shell
python3 -m pip install dbt-risingwave
```

2. Get `RisingWave` running

Please follow [this](https://www.risingwave.dev/docs/current/get-started/) guide to set up a functional RisingWave instance.

3. Configure the `dbt` profile file

The profile file is located in `~/.dbt/profiles.yml`. Here's an example of how to use it with RisingWave.

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

4. Run `dbt debug` to check whether the configuration is correct.

### Controlling streaming parallelism

RisingWave exposes the session variables `streaming_parallelism` and `streaming_max_parallelism`. When these values are provided in a profile (see the example above) the adapter issues the corresponding `SET` statements as soon as a connection is opened, ensuring every model uses the desired streaming configuration.

You can also scope the settings to specific models via `config()` (or in `dbt_project.yml`). The adapter now injects the statements ahead of every model's SQL:

```sql
{{ config(materialized='materialized_view', streaming_parallelism=2, streaming_max_parallelism=8) }}

select ...
```

## Models

The dbt models for managing data transformations in RisingWave are similar to typical dbt sql models. The main differences are the materializations. We customized the materializations to fit the data processing model of RisingWave.

| Materializations      | INFO                   |
| ---------------------- | --------------------- |
| materialized_view      | Create a materialized view. This materialization corresponds to the incremental one in dbt. To use this materialization, add {{ config(materialized='materialized_view') }} to your model SQL files. **NEW: Supports zero downtime rebuilds using ALTER MATERIALIZED VIEW SWAP syntax when both model config has zero_downtime={'enabled': true} AND --vars 'zero_downtime: true' is provided (requires RisingWave v2.2+).**                      |
| materializedview       | (Deprecated) only for backward compatibility, use `materialized_view` instead. **Zero downtime rebuilds are not supported - please migrate to `materialized_view` to use this feature.**                      |
| ephemeral              | This materialization uses common table expressions in RisingWave under the hood. To use this materialization, add {{ config(materialized='ephemeral') }} to your model SQL files.                      |
| table                  | Create a table. To use this materialization, add {{ config(materialized='table') }} to your model SQL files. |
| view                   | Create a view. To use this materialization, add {{ config(materialized='view') }} to your model SQL files. |
| incremental            | Use `materialized_view` instead if possible, since RisingWave is designed to use a materialized view to manage data transformation in an incremental way. From v1.7.3, dbt-risingwave supports `incremental` model to give users better control of when to update their model. This model will update the table in a batch way incrementally.                     |
| source                 | Define a source {{ config(materialized='source') }}. You need to provide your create source statement as a whole in this model.                      |
| table_with_connector   | Define a table with a connector {{ config(materialized='table_with_connector') }}. You need to provide your create table with connector statement as a whole in this model. Because dbt `table` has its own semantics, RisingWave uses `table_with_connector` to distinguish itself from it.  The connector is optional if you just want to define a table without anything connector.                    |
| sink                   | Define a sink {{ config(materialized='sink') }}. You need to provide your create sink statement as a whole in this model.                      |

To learn how to use, you can check RisingWave's official example [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark).

## Zero Downtime Materialized View Rebuilds

**NEW FEATURE**: dbt-risingwave now supports zero downtime rebuilds for materialized views when SQL definitions change. This feature:

- Uses RisingWave's `ALTER MATERIALIZED VIEW SWAP` syntax for atomic updates
- **Requires RisingWave v2.2 or later** - the `ALTER MATERIALIZED VIEW SWAP` syntax is only available in RisingWave v2.2+
- **Dual-layer safety** - requires both model config `zero_downtime={'enabled': true}` AND runtime flag `--vars 'zero_downtime: true'`
- Maintains service availability during model updates when enabled
- Provides runtime control over when zero downtime rebuilds are used

For detailed documentation, see [ZERO_DOWNTIME_MV_README.md](ZERO_DOWNTIME_MV_README.md).

## DBT RUN behavior

- `dbt run`: only create new models (if not exists) without dropping any models.
- `dbt run --full-refresh`: drop models and create the new ones. This command can make sure your streaming pipelines are consistent with what you define in dbt models.

## Graph operators

[Graph operators](https://docs.getdbt.com/reference/node-selection/graph-operators) is useful when you want to only recreate a subset of your models.

```sh
dbt run --select "my_model+"         # select my_model and all children
dbt run --select "+my_model"         # select my_model and all parents
dbt run --select "+my_model+"         # select my_model, and all of its parents and children
```

## Tests

All items below have been tested against the latest RisingWave daily build version.

- [x] Offical example [jaffle_shop](https://github.com/dbt-labs/jaffle_shop) is tested.
- [x] RisingWave offical example [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark) is tested.
