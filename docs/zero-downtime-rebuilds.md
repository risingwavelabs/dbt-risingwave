# Zero-Downtime Rebuilds and Sink Cut-Overs

## Overview

This feature enables zero-downtime rebuilds for materialized views and views, and
zero-downtime cut-over for supported sinks.

- Materialized views use `ALTER MATERIALIZED VIEW ... SWAP WITH ...`
- Views use `ALTER VIEW ... SWAP WITH ...`
- Sinks use `REPLACE SINK ... FROM relation`

This keeps the original object name available during the update.

## Requirements

- Materialized view swap requires RisingWave v2.2 or later.
- Zero-downtime materialized view rebuilds are supported only on `materialized_view`.
- The deprecated `materializedview` materialization is not supported.
- View swap is supported on the `view` materialization.
- Sink cut-over requires a RisingWave build containing `REPLACE SINK` (planned for
  RisingWave v3.1.0).
- Sink cut-over is supported only for adapter-managed `sink` models whose SQL renders to
  one upstream relation. Raw sink DDL and `CREATE SINK ... AS SELECT ...` are not rewritten.

## How It Works

When a model already exists and zero downtime is enabled, the adapter:

1. Creates a temporary object with the new definition.
2. For an indexed materialized view, builds the configured indexes on the temporary
   object and waits for their backfill to finish.
3. Swaps the temporary object with the original object.
4. Promotes the prebuilt indexes to their canonical dbt names. If a previous index
   already owns a canonical name, it is renamed and remains attached to the old object.
5. Either preserves or safely drops the old object, depending on `immediate_cleanup`
   and remaining dependencies.

Temporary objects use the naming pattern `{original_name}_dbt_zero_down_tmp_{timestamp}`.

RisingWave does not provide an atomic `ALTER INDEX ... SWAP WITH ...` command. The
adapter instead creates each new index under a unique temporary name, waits for it,
and performs metadata-only index renames after the materialized-view swap. Queries
always have a ready index attached to the active materialized view; only the index
name handoff is non-atomic.

For a supported sink, the adapter instead issues `REPLACE SINK` directly. RisingWave
creates a replacement sink job, drains the old sink at the cut-over barrier, and exposes
the replacement under the original name. No temporary dbt relation is created.

## Enabling the Feature

Zero-downtime operations require both model configuration and a runtime flag.

### Model Configuration

For a materialized view:

```sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

select *
from {{ ref('source_table') }}
```

For a view:

```sql
{{ config(
    materialized='view',
    zero_downtime={'enabled': true}
) }}

select *
from {{ ref('source_table') }}
```

For an adapter-managed sink, the model body must be only an upstream relation:

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
    format_parameters={},
    zero_downtime={'enabled': true}
) }}

{{ ref('orders_mv') }}
```

Do not wrap the relation in `SELECT * FROM ...`; the current RisingWave command does not
support `REPLACE SINK ... AS query`.

### Runtime Flag

```bash
dbt run --vars 'zero_downtime: true'
```

If the runtime flag is omitted, the adapter falls back to the normal rebuild flow even when the model is configured for zero downtime.

## Cleanup Behavior

This section applies to the temporary objects created by view and materialized-view swaps;
sink replacement does not create a dbt temporary relation.

By default, temporary objects are preserved after the swap to avoid breaking downstream dependencies.

```sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': false}
) }}
```

To try to drop the temporary object immediately after the swap:

```sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}
```

Immediate cleanup is dependency-safe and best-effort. RisingWave `SWAP WITH` keeps existing downstream objects attached to the pre-swap object ID, now renamed to the temporary object. If any dependent object still references that temporary object, the adapter preserves it even when `immediate_cleanup` is `true`; it does not use `CASCADE` for zero-downtime temporary object cleanup.

Indexes owned by a temporary materialized view do not by themselves prevent cleanup.
RisingWave drops those indexes together with their parent materialized view. They are
kept while the old materialized view is preserved, so downstream users of the old
object do not lose its index before the object is safe to remove.

For a chain such as `mv1 -> mv2 -> mv3`, updating only `mv1` can leave `mv2` and `mv3` reading from the preserved temporary `mv1` object. Rebuild dependent models when they should move to the new upstream definition:

```bash
dbt run --select "mv1+" --vars 'zero_downtime: true'
```

Then run cleanup after dependent models have been rebuilt:

```bash
dbt run-operation cleanup_temp_objects
```

One cleanup invocation repeatedly removes the current dependency-safe leaf objects until
it reaches a fixed point. This fully drains a rebuilt multi-level temporary chain in the
same invocation, regardless of object-name order. The helper never uses `CASCADE`.

If non-temporary objects still reference a temporary object, cleanup preserves it and
reports the remaining objects. Rebuild those downstream objects before running cleanup
again. A dry run reports what is safe in the current catalog state; it does not simulate
the additional objects that would become safe after those reported drops.

## When Zero-Downtime Mode Applies

The adapter uses zero-downtime mode only when all of the following are true:

1. The relation already exists.
2. The run is not using `--full-refresh`.
3. The model has `zero_downtime={'enabled': true}`.
4. The command includes `--vars 'zero_downtime: true'`.

Otherwise, dbt-risingwave uses the standard handling path.

For sinks, `--full-refresh` deliberately keeps the existing drop/create behavior because
`REPLACE SINK` always uses `snapshot=false` and cannot provide full-refresh semantics.
Run a sink cut-over without `--full-refresh`.

## Current Sink Limitations

The current RisingWave implementation rejects `REPLACE SINK` for:

- exactly-once sinks, including Iceberg sinks that use exactly-once state;
- sink-into-table;
- auto schema change sinks;
- sinks using `since_timestamp`; and
- query-based `REPLACE SINK ... AS query`.

The replacement starts from the cut-over barrier and does not backfill historical rows
from the new upstream. RisingWave gives the replacement a new sink object id, so privileges
configured through dbt are reapplied after replacement; privileges managed outside dbt are
not preserved automatically.

## Manual Cleanup Helpers

The adapter includes helper macros for listing and cleaning up preserved view and
materialized-view temporary objects. They do not apply to sinks.

```bash
dbt run-operation list_temp_objects
dbt run-operation cleanup_temp_objects --args '{"dry": true}'
dbt run-operation cleanup_temp_objects
```

You can scope these helpers to a schema:

```bash
dbt run-operation list_temp_objects --args '{"schema_name": "public"}'
dbt run-operation cleanup_temp_objects --args '{"schema_name": "public"}'
```
