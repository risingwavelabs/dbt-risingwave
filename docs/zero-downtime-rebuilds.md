# Zero Downtime Rebuilds for Materialized Views and Views

## Overview

This feature enables zero-downtime rebuilds for both materialized views and views by using swap-based updates.

- Materialized views use `ALTER MATERIALIZED VIEW ... SWAP WITH ...`
- Views use `ALTER VIEW ... SWAP WITH ...`

This keeps the original object name available during the update.

## Requirements

- Materialized view swap requires RisingWave v2.2 or later.
- Zero-downtime materialized view rebuilds are supported only on `materialized_view`.
- The deprecated `materializedview` materialization is not supported.
- View swap is supported on the `view` materialization.

## How It Works

When a model already exists and zero downtime is enabled, the adapter:

1. Creates a temporary object with the new definition.
2. Swaps the temporary object with the original object.
3. Either preserves or safely drops the old object, depending on `immediate_cleanup` and remaining dependencies.

Temporary objects use the naming pattern `{original_name}_dbt_zero_down_tmp_{timestamp}`.

## Enabling the Feature

Zero-downtime rebuilds require both model configuration and a runtime flag.

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

### Runtime Flag

```bash
dbt run --vars 'zero_downtime: true'
```

If the runtime flag is omitted, the adapter falls back to the normal rebuild flow even when the model is configured for zero downtime.

## Cleanup Behavior

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

For a chain such as `mv1 -> mv2 -> mv3`, updating only `mv1` can leave `mv2` and `mv3` reading from the preserved temporary `mv1` object. Rebuild dependent models when they should move to the new upstream definition:

```bash
dbt run --select "mv1+" --vars 'zero_downtime: true'
```

Then run cleanup after dependent models have been rebuilt:

```bash
dbt run-operation cleanup_temp_objects
```

The cleanup helper also skips temporary objects that still have dependents. Run it again after rebuilding more downstream objects if it reports preserved objects.

## When Swap-Based Rebuilds Apply

The adapter uses zero-downtime rebuilds only when all of the following are true:

1. The relation already exists.
2. The run is not using `--full-refresh`.
3. The model has `zero_downtime={'enabled': true}`.
4. The command includes `--vars 'zero_downtime: true'`.

Otherwise, dbt-risingwave uses the standard handling path.

## Manual Cleanup Helpers

The adapter includes helper macros for listing and cleaning up preserved temporary objects.

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
