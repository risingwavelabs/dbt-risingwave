# Zero Downtime Materialized View Rebuild

## Overview

This feature enables zero downtime rebuilds of Materialized Views (MVs) by leveraging RisingWave's `ALTER MATERIALIZED VIEW SWAP` syntax for seamless transitions during model updates.

## How It Works

When a Materialized View definition changes, instead of dropping and recreating the MV (which causes downtime), this feature follows a three-step process:

1. **Create Temporary MV**: Creates a new Materialized View with a temporary name using the updated SQL definition
2. **Atomic Swap**: Uses `ALTER MATERIALIZED VIEW {original} SWAP WITH {temp}` to atomically exchange the original and temporary MVs
3. **Cleanup**: Drops the old MV (now using the temporary name)

This ensures the original MV name remains available throughout the entire process, achieving true zero downtime updates.

## Usage

### Enabling Zero Downtime Rebuilds

Zero downtime rebuilds are **disabled by default** and must be explicitly enabled. To use this feature, add the configuration to your model:

```sql
-- models/my_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime=true
) }}

SELECT 
    id,
    name,
    created_at,
    updated_at  -- Adding new field
FROM {{ ref('source_table') }}
```

### Default Behavior (Zero Downtime Disabled)

By default, zero downtime functionality is disabled and uses traditional configuration change handling:

```sql
-- models/my_model.sql
{{ config(materialized='materialized_view') }}

SELECT * FROM {{ ref('source_table') }}
```

### Explicitly Disabling Zero Downtime

To explicitly indicate the use of traditional handling, you can set:

```sql
-- models/my_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime=false
) }}

SELECT * FROM {{ ref('source_table') }}
```

## When Zero Downtime Rebuilds Trigger

Zero downtime rebuilds are triggered in the following scenarios (only when `zero_downtime=true`):

1. **Existing MV**: A Materialized View must already exist
2. **Non-full-refresh Mode**: Only applies when not using `--full-refresh`
3. **Explicitly Enabled**: Must have `zero_downtime=true` configured

## When Traditional Handling Is Used

The following scenarios will use traditional configuration change handling:

1. **Default Behavior**: When `zero_downtime=true` is not set (default)
2. **Full Refresh Mode**: When using the `--full-refresh` parameter
3. **Initial Creation**: When the MV doesn't exist (first-time creation)
4. **Explicitly Disabled**: When `zero_downtime=false` is set

## Technical Details

### Temporary MV Naming Convention

Temporary MVs follow the naming pattern: `{original_name}_tmp_{timestamp}`

The timestamp format is: `YYYYMMDD_HHMMSS_microseconds`

Example: `my_model_tmp_20231201_143022_123456`

### Implementation Macros

The feature relies on two core macros:

1. **`risingwave__create_materialized_view_with_temp_name`**: Generates SQL to create an MV with a temporary name
2. **`risingwave__swap_materialized_views`**: Generates SQL for the MV swap operation

### Execution Flow

When zero downtime rebuild is enabled, the following SQL operations are executed:

```sql
-- Step 1: Create temporary materialized view (main statement)
CREATE MATERIALIZED VIEW my_model_tmp_20231201_143022_123456 AS ...

-- Step 2: Swap the materialized views
ALTER MATERIALIZED VIEW my_model SWAP WITH my_model_tmp_20231201_143022_123456

-- Step 3: Clean up old materialized view
DROP MATERIALIZED VIEW IF EXISTS my_model_tmp_20231201_143022_123456 CASCADE
```

## Log Output

When zero downtime rebuild is active, you'll see this message in the logs:

```
Using zero downtime rebuild with SWAP for materialized view update.
```

## Error Handling

If errors occur during the zero downtime rebuild process:

1. **Temporary MV Creation Failure**: The original MV remains intact, with no impact on existing services
2. **SWAP Operation Failure**: Attempts to clean up the temporary MV
3. **Cleanup Failure**: May require manual cleanup of orphaned temporary MVs

## Feature Compatibility

- ✅ **Indexes**: Supports index recreation after rebuild
- ✅ **Documentation**: Supports documentation persistence
- ✅ **Hooks**: Compatible with pre/post hooks
- ✅ **Configuration Changes**: Works with existing configuration change handling

## Performance Considerations

- Zero downtime rebuilds require additional storage space for temporary MVs
- SWAP operations may have brief performance impact under high load
- Consider scheduling large MV rebuilds during low-traffic periods

## Example Scenarios

### Scenario 1: Enabling Zero Downtime Rebuild

```sql
-- Enable zero downtime functionality
{{ config(
    materialized='materialized_view',
    zero_downtime=true
) }}

-- Original definition
SELECT id, name FROM users

-- Updated definition
SELECT id, name, email FROM users
```

With zero downtime rebuild enabled, user queries will not be interrupted during the update.

### Scenario 2: Using Default Behavior

```sql
-- Default behavior (no zero downtime)
{{ config(materialized='materialized_view') }}

SELECT 
    user_id, 
    COUNT(*) as order_count 
FROM orders 
GROUP BY user_id
```

Uses traditional configuration change handling.

## Best Practices

1. **Selective Enablement**: Only enable this feature in production environments where zero downtime is truly required
2. **Monitor Temporary MVs**: Regularly check for and clean up any orphaned temporary MVs
3. **Storage Planning**: Ensure adequate storage space to accommodate temporary MVs
4. **Testing**: Thoroughly test the feature in development environments before production use
5. **Rollback Planning**: Prepare rollback procedures for unexpected scenarios

## Troubleshooting

### Common Issues

1. **Temporary MV Name Conflicts**: Extremely rare due to microsecond-precision timestamps
2. **Permission Issues**: Ensure the dbt user has CREATE, DROP, and ALTER permissions for MVs
3. **Insufficient Storage**: Monitor storage usage to ensure adequate space

### Debugging Tips

1. Enable verbose logging: `dbt run --log-level debug`
2. Check RisingWave logs for detailed SWAP operation information
3. Use `dbt ls` command to verify model states
4. Monitor for orphaned temporary MVs in your RisingWave instance

## Configuration Reference

| Config Option | Default | Description |
|---------------|---------|-------------|
| `zero_downtime` | `false` | Enables zero downtime rebuilds when set to `true` |

## Limitations

- Requires RisingWave support for `ALTER MATERIALIZED VIEW SWAP` syntax
- Only applicable to `materialized_view` and `materializedview` materializations
- Not compatible with full refresh operations
- Requires additional storage capacity during rebuild process 