# dbt-risingwave

A [RisingWave](https://github.com/risingwavelabs/risingwave) 
adapter plugin for [dbt](https://www.getdbt.com/).

**RisingWave** is a cloud-native streaming database that uses SQL as the interface language. It is designed to reduce the complexity and cost of building real-time applications. https://www.risingwave.com

**dbt** enables data analysts and engineers to transform their data using the same practices that software engineers use to build applications. [Use dbt for data transformations in RisingWave](https://docs.risingwave.com/docs/current/use-dbt/)

## Getting started

The package has not been published to PyPI, please install it via git.

1. Install `dbt-risingwave`

```shell
python3 -m pip install dbt-risingwave
```

2. Get `RisingWave` running

Please follow [this](https://www.risingwave.dev/docs/current/get-started/) guide to setup a functional RisingWave instance.

3. Configure `dbt` profile file

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

4. Run `dbt debug` to check whether configuration is correct.

## Models

The dbt models for managing data transformations in RisingWave is similar to typical dbt sql models. The main differences are the materializations. We customized the materializations to fit the data processing model of RisingWave.

| Materializations      | INFO                   |
| ---------------------- | --------------------- |
| materialized_view      | Create a materialized view. This materialization is corresponding to the incremental one in dbt. To use this materialization, add {{ config(materialized='materialized_view') }} to your model SQL files.                      |
| materializedview       | (Deprecated) only for backward compatibility, use `materialized_view` instead                      |
| ephemeral              | This materialization uses common table expressions in RisingWave under the hood. To use this materialization, add {{ config(materialized='ephemeral') }} to your model SQL files.                      |
| table                  | Create a table. To use this materialization, add {{ config(materialized='table') }} to your model SQL files. |
| view                   | Create a view. To use this materialization, add {{ config(materialized='view') }} to your model SQL files. |
| incremental            | Use `materialized_view` instead. Since RisingWave is designed to use materialized view to manage data transformation in an incremental way, you don’t need to use the incremental materialization and can just use materializedview.                     |
| source                 | Define a source {{ config(materialized='source') }}. You need to provide your create source statement as a whole in this model.                      |
| table_with_connector   | Define a table with a connector {{ config(materialized='table_with_connector') }}. You need to provide your create table with connector statement as a whole in this model. Because dbt `table` has its own semantics, RisingWave use `table_with_connector` to distinguish itself from it.                      |
| sink                   | Define a sink {{ config(materialized='sink') }}. You need to provide your create sink statement as a whole in this model.                      |

To learn how to use, you can check RisingWave offical example [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark).


## Tests

All items below have been tested against the the latest RisingWave daily build verison.

- [x] Offical example [jaffle_shop](https://github.com/dbt-labs/jaffle_shop) is tested.
- [x] RisingWave offical example [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark) is tested.
