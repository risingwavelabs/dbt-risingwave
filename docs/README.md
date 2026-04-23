# Documentation

This directory contains the adapter-specific documentation that used to be mixed into the root README.

## Guides

- [configuration.md](configuration.md): profile settings, model configuration, and sink options
- [functions.md](functions.md): first-version SQL scalar function support and its limits
- [zero-downtime-rebuilds.md](zero-downtime-rebuilds.md): zero-downtime rebuild flow for materialized views and views

## Start Here

If you are new to the adapter:

1. Read the root [README.md](../README.md) for installation and basic project setup.
2. Read [configuration.md](configuration.md) for RisingWave-specific configuration.
3. Read [functions.md](functions.md) if you plan to manage SQL scalar UDFs with dbt.
4. Read [zero-downtime-rebuilds.md](zero-downtime-rebuilds.md) if you plan to use swap-based rebuilds.
