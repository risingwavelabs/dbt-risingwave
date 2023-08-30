# dbt-risingwave

A [RisingWave](https://github.com/risingwavelabs/risingwave) 
adapter plugin for [dbt](https://www.getdbt.com/).

**RisingWave** is a cloud-native streaming database that uses SQL as the interface language. It is designed to reduce the complexity and cost of building real-time applications. https://www.risingwave.com

**dbt** enables data analysts and engineers to transform their data using the same practices that software engineers use to build applications.

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


## Current Status

All items below have been tested against the the latest RisingWave daily build verison.

- [x] `dbt seed/run/test/docs` works.
- [x] Offical example [jaffle_shop](https://github.com/dbt-labs/jaffle_shop) is tested.
- [x] RisingWave offical example [dbt_rw_nexmark](https://github.com/risingwavelabs/dbt_rw_nexmark) is tested.
