# Zero Downtime Materialized View Rebuild

## Overview

This feature enables zero downtime rebuilds of Materialized Views (MVs) by leveraging RisingWave's `ALTER MATERIALIZED VIEW SWAP` syntax for seamless transitions during model updates.

## Requirements

**⚠️ RisingWave Version Requirement**: This feature requires **RisingWave v2.2 or later**. The `ALTER MATERIALIZED VIEW SWAP` syntax is only available starting from RisingWave v2.2. Using this feature with earlier versions will result in SQL syntax errors.

**⚠️ Materialization Requirement**: This feature is only available for the `materialized_view` materialization. The deprecated `materializedview` materialization does not support zero downtime rebuilds. If you are using `materializedview`, please migrate to `materialized_view` to access this feature.

## How It Works

When a Materialized View definition changes, instead of dropping and recreating the MV (which causes downtime), this feature follows a three-step process:

1. **Create Temporary MV**: Creates a new Materialized View with a temporary name using the updated SQL definition
2. **Atomic Swap**: Uses `ALTER MATERIALIZED VIEW {original} SWAP WITH {temp}` to atomically exchange the original and temporary MVs
3. **Conditional Cleanup**: Optionally drops the old MV (now using the temporary name) based on configuration

This ensures the original MV name remains available throughout the entire process, achieving true zero downtime updates.

## Usage

### Enabling Zero Downtime Rebuilds

Zero downtime rebuilds are **disabled by default** and must be explicitly enabled. To use this feature, add the configuration to your model:

```sql
-- models/my_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

SELECT 
    id,
    name,
    created_at,
    updated_at  -- Adding new field
FROM {{ ref('source_table') }}
```

### Configuring Cleanup Behavior

By default, temporary MVs are **preserved** to avoid affecting downstream dependencies. You can control cleanup behavior:

```sql
-- Immediate cleanup (may affect downstream MVs)
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}

-- Deferred cleanup (default, preserves downstream dependencies)
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': false}
) }}
```

### Default Behavior (Zero Downtime Disabled)

By default, zero downtime functionality is disabled and uses traditional configuration change handling:

```sql
-- models/my_model.sql
{{ config(materialized='materialized_view') }}

SELECT * FROM {{ ref('source_table') }}
```

## Temporary MV Management

### Understanding the Cleanup Strategy

**Default Behavior (Recommended)**: Temporary MVs are preserved after swap to maintain downstream dependencies. This prevents CASCADE drops from affecting dependent MVs, ensuring true zero downtime.

**Immediate Cleanup**: When enabled, temporary MVs are dropped immediately after swap. This may affect downstream MVs if they depend on the original MV.

### Managing Temporary MVs with dbt Commands

#### Listing Temporary MVs

```bash
# List all temporary MVs across all schemas
dbt run-operation list_temp_mvs

# List temporary MVs in a specific schema
dbt run-operation list_temp_mvs --args '{"schema_name": "public"}'
```

#### Cleaning Up Temporary MVs

```bash
# Dry run - see what would be cleaned up (safe to run)
dbt run-operation cleanup_temp_mvs --args '{"dry": true}'

# Dry run for specific schema
dbt run-operation cleanup_temp_mvs --args '{"schema_name": "public", "dry": true}'

# Actually clean up temporary MVs (caution: this will drop MVs)
dbt run-operation cleanup_temp_mvs

# Clean up temporary MVs in specific schema
dbt run-operation cleanup_temp_mvs --args '{"schema_name": "public"}'
```

**Note**: These commands will display output directly to the console without requiring special log level settings.

### Alternative: Using Internal Macros

For advanced users, you can also call the internal macros directly:

```bash
# List temporary MVs (internal macro)
dbt run-operation risingwave__list_temp_materialized_views

# Cleanup with internal macro
dbt run-operation risingwave__cleanup_temp_materialized_views --args '{"dry_run": false}'
```

## When Zero Downtime Rebuilds Trigger

Zero downtime rebuilds are triggered in the following scenarios (only when `zero_downtime={'enabled': true}`):

1. **Existing MV**: A Materialized View must already exist
2. **Non-full-refresh Mode**: Only applies when not using `--full-refresh`
3. **Explicitly Enabled**: Must have `zero_downtime={'enabled': true}` configured

## When Traditional Handling Is Used

The following scenarios will use traditional configuration change handling:

1. **Default Behavior**: When `zero_downtime={'enabled': true}` is not set (default)
2. **Full Refresh Mode**: When using the `--full-refresh` parameter
3. **Initial Creation**: When the MV doesn't exist (first-time creation)
4. **Explicitly Disabled**: When `zero_downtime={'enabled': false}` is set

## Technical Details

### Temporary MV Naming Convention

Temporary MVs follow the naming pattern: `{original_name}_dbt_zero_down_tmp_{timestamp}`

The timestamp format is an ISO format with UTC timezone, with special characters replaced by underscores for database compatibility.

Example: `my_model_dbt_zero_down_tmp_20231201T143022_123456Z`

**Security Note**: The specific naming pattern `_dbt_zero_down_tmp_` is used to avoid conflicts with user-created tables that might contain generic patterns like `_tmp_`.

### Implementation Macros

The feature relies on several core macros:

1. **`risingwave__create_materialized_view_with_temp_name`**: Generates SQL to create an MV with a temporary name
2. **`risingwave__swap_materialized_views`**: Generates SQL for the MV swap operation
3. **`risingwave__list_temp_materialized_views`**: Lists temporary MVs for cleanup management
4. **`risingwave__cleanup_temp_materialized_views`**: Utility for cleaning up temporary MVs

### Execution Flow

When zero downtime rebuild is enabled, the following SQL operations are executed:

```sql
-- Step 1: Create temporary materialized view (main statement)
CREATE MATERIALIZED VIEW my_model_dbt_zero_down_tmp_20231201T143022_123456Z AS ...

-- Step 2: Swap the materialized views
ALTER MATERIALIZED VIEW my_model SWAP WITH my_model_dbt_zero_down_tmp_20231201T143022_123456Z

-- Step 3: Conditional cleanup (only if immediate_cleanup=true)
DROP MATERIALIZED VIEW IF EXISTS my_model_dbt_zero_down_tmp_20231201T143022_123456Z CASCADE
```

## Log Output

### Zero Downtime Rebuild
```
Using zero downtime rebuild with SWAP for materialized view update.
```

### Cleanup Behavior
```
# When immediate_cleanup=false (default)
Preserving temporary materialized view for downstream dependencies: my_model_dbt_zero_down_tmp_20231201T143022_123456Z
Manual cleanup required: DROP MATERIALIZED VIEW IF EXISTS my_model_dbt_zero_down_tmp_20231201T143022_123456Z;

# When immediate_cleanup=true
Immediately cleaning up temporary materialized view: my_model_dbt_zero_down_tmp_20231201T143022_123456Z
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
- ✅ **Downstream Dependencies**: Preserves downstream MV dependencies by default

## Performance Considerations

- Zero downtime rebuilds require additional storage space for temporary MVs
- SWAP operations may have brief performance impact under high load
- Consider scheduling large MV rebuilds during low-traffic periods
- Temporary MVs may accumulate if not cleaned up regularly

## Example Scenarios

### Scenario 1: Safe Zero Downtime Rebuild (Recommended)

```sql
-- Safe approach: preserve downstream dependencies
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

SELECT id, name, email FROM users
```

This preserves temporary MVs to protect downstream dependencies. Clean up manually when safe.

### Scenario 2: Immediate Cleanup (Use with Caution)

```sql
-- Immediate cleanup: may affect downstream MVs
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}

SELECT id, name, email FROM users
```

This immediately cleans up temporary MVs but may affect downstream dependencies.

## Best Practices

1. **Use Default Cleanup Strategy**: Keep `zero_downtime_immediate_cleanup=false` to protect downstream dependencies
2. **Regular Cleanup**: Schedule periodic cleanup of temporary MVs using the provided utilities
3. **Monitor Storage**: Track storage usage as temporary MVs accumulate
4. **Test Dependencies**: Verify downstream MV behavior before enabling immediate cleanup
5. **Cleanup Automation**: Consider automating temporary MV cleanup in your deployment pipeline
6. **Resource Planning**: Ensure cluster has sufficient capacity for doubled resource usage during rebuilds
7. **Sink Management**: 
   - **Document Sink Dependencies**: Maintain documentation of which MVs have downstream Sinks
   - **Plan Sink Updates**: Prepare Sink update procedures before MV rebuilds
   - **Test Sink Compatibility**: Verify Sink behavior with new MV schemas in non-production environments
   - **Consider Maintenance Windows**: Schedule MV rebuilds with Sinks during low-impact periods
8. **Monitoring and Alerting**:
   - Set up alerts for temporary MV accumulation
   - Monitor cluster resource usage during rebuilds
   - Track rebuild success/failure rates
9. **Staged Rollouts**: Test zero downtime rebuilds on smaller, less critical MVs first
10. **Documentation**: Keep team documentation updated with zero downtime procedures and Sink update workflows

## Cleanup Workflow

### Recommended Cleanup Process

1. **Complete Model Updates**: Finish updating all dependent MVs
2. **Verify Dependencies**: Ensure all downstream MVs are functioning correctly
3. **Clean Up Safely**: Use the cleanup utilities to remove temporary MVs

```sql
-- Step 1: List temporary MVs
{{ risingwave__list_temp_materialized_views() }}

-- Step 2: Dry run cleanup
{{ risingwave__cleanup_temp_materialized_views(dry_run=true) }}

-- Step 3: Actual cleanup
{{ risingwave__cleanup_temp_materialized_views(dry_run=false) }}
```

## Troubleshooting

### Common Issues

1. **Accumulating Temporary MVs**: Set up regular cleanup processes
2. **Storage Growth**: Monitor disk usage and clean up temporary MVs regularly
3. **Permission Issues**: Ensure the dbt user has CREATE, DROP, and ALTER permissions for MVs
4. **Downstream MV Failures**: Check if immediate cleanup is affecting dependent MVs
5. **Sink Connection Issues**: Verify that downstream Sinks are properly updated after MV rebuilds
6. **Resource Exhaustion**: Monitor cluster resources during rebuilds, especially for large MVs
7. **Schema Mismatch**: Ensure Sink schemas are compatible with rebuilt MV schemas

### Debugging Tips

1. Enable verbose logging: `dbt run --log-level debug`
2. Check RisingWave logs for detailed SWAP operation information
3. Use `dbt ls` command to verify model states
4. Monitor for orphaned temporary MVs in your RisingWave instance
5. Use the provided utilities to inspect and manage temporary MVs
6. **Sink Debugging**:
   - Check Sink status after MV rebuilds: `SHOW SINKS;`
   - Verify Sink schema compatibility with new MV schema
   - Monitor Sink error logs for schema-related issues
7. **Resource Monitoring**:
   - Monitor cluster memory usage during rebuilds
   - Check for resource constraints in RisingWave logs
   - Track CPU and storage utilization patterns

## Configuration Reference

| Config Option | Default | Description |
|---------------|---------|-------------|
| `zero_downtime` | `{}` | Dictionary configuration for zero downtime rebuilds |
| `zero_downtime.enabled` | `false` | Enables zero downtime rebuilds when set to `true` |
| `zero_downtime.immediate_cleanup` | `false` | Controls whether temporary MVs are immediately dropped after swap |

### Configuration Format

```sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': false}
) }}
```

## Limitations

### Core Limitations

- **RisingWave Version Requirement**: Requires **RisingWave v2.2 or later** for `ALTER MATERIALIZED VIEW SWAP` syntax support
- **Materialization Compatibility**: Only applicable to `materialized_view` materialization (not available for the deprecated `materializedview` materialization)
- **Full Refresh Incompatibility**: Not compatible with full refresh operations (`--full-refresh`)
- **Storage Requirements**: Requires additional storage capacity during rebuild process

### Downstream Sink Handling

**⚠️ Critical Limitation**: Zero downtime rebuilds **do not automatically handle downstream Sinks** that depend on the materialized view.

When a materialized view has downstream Sinks:
1. **Manual Intervention Required**: You must manually recreate or update Sinks after the MV rebuild
2. **Pipeline Disruption**: The data pipeline may be temporarily disrupted until Sinks are updated
3. **Sink Dependencies**: Sinks will continue to reference the old MV definition until manually updated

**Example Scenario**:
```sql
-- Original MV
CREATE MATERIALIZED VIEW user_stats AS SELECT id, name FROM users;

-- Downstream Sink
CREATE SINK user_sink FROM user_stats WITH (...);

-- After zero downtime rebuild with new column:
-- MV now has: SELECT id, name, email FROM users;
-- But Sink still references old schema - manual update required
```

**Recommended Approach for Sinks**:
1. Plan MV updates during maintenance windows when Sink disruption is acceptable
2. Update Sinks immediately after MV rebuild
3. Consider using traditional rebuild methods for MVs with critical downstream Sinks

### Resource and Performance Impact

**⚠️ Resource Doubling**: During zero downtime rebuilds, your cluster will temporarily experience **doubled resource usage**:

- **Memory Usage**: Both old and new MVs exist simultaneously, doubling memory consumption
- **CPU Load**: Concurrent processing of two MVs increases CPU utilization
- **Storage Space**: Requires storage for both versions until cleanup
- **Network I/O**: Data transfer for maintaining both MVs impacts network resources

**Planning Considerations**:
- Ensure sufficient cluster capacity before initiating large MV rebuilds
- Monitor resource usage during rebuild operations
- Schedule rebuilds during low-traffic periods
- Consider staggered rebuilds for multiple large MVs

### Temporary MV Management

**⚠️ Manual Cleanup Required**: Zero downtime rebuilds create temporary MVs that require manual cleanup:

**Default Behavior**:
- Temporary MVs are **preserved by default** to protect downstream dependencies
- These MVs consume cluster resources until manually removed
- Accumulation of temporary MVs can lead to resource exhaustion

**Cleanup Responsibilities**:
```bash
# Regular cleanup is essential - run these commands periodically:
dbt run-operation list_temp_mvs                    # Check for temporary MVs
dbt run-operation cleanup_temp_mvs --args '{"dry": true}'  # Preview cleanup (dry run)
dbt run-operation cleanup_temp_mvs                 # Execute cleanup
```

**Monitoring Requirements**:
- Set up regular monitoring for temporary MV accumulation
- Establish cleanup schedules in your deployment pipeline
- Track storage usage growth from temporary MVs

### Production Considerations

- **Testing Required**: Thoroughly test zero downtime rebuilds in non-production environments
- **Rollback Planning**: Have rollback procedures ready in case of rebuild failures  
- **Monitoring Setup**: Implement monitoring for resource usage during rebuilds
- **Documentation**: Document your specific Sink update procedures
- **Team Coordination**: Ensure team awareness of manual cleanup requirements

## Additional Notes

- This feature is designed to work with RisingWave's `ALTER MATERIALIZED VIEW SWAP` syntax, which is only supported in **RisingWave v2.2 and later**.
- Ensure that your RisingWave version is v2.2 or higher for this feature to work properly.
- If you encounter issues with this feature on earlier versions, please upgrade to RisingWave v2.2+ or disable the zero downtime feature by removing `zero_downtime=true` from your model configuration. 