# Zero Downtime Rebuilds for Materialized Views and Views

## Overview

This feature enables zero downtime rebuilds of both Materialized Views (MVs) and Views by using different strategies depending on the materialization type:

- **Materialized Views**: Uses RisingWave's `ALTER MATERIALIZED VIEW SWAP` syntax for atomic exchanges
- **Views**: Uses `CREATE OR REPLACE VIEW` for immediate updates

This ensures seamless transitions during model updates with minimal downtime impact on dependent objects.

## Requirements

**⚠️ RisingWave Version Requirement**: 
- For Materialized Views: Requires **RisingWave v2.2 or later** for `ALTER MATERIALIZED VIEW SWAP` syntax support
- For Views: Compatible with all RisingWave versions that support `CREATE OR REPLACE VIEW`

**⚠️ Materialization Support**: 
- **Materialized Views**: Only the `materialized_view` materialization is supported (the deprecated `materializedview` materialization does not support zero downtime rebuilds)
- **Views**: The `view` materialization is fully supported

## How It Works

The zero downtime rebuild feature uses different strategies depending on the materialization type:

### Materialized Views

When a Materialized View definition changes, instead of dropping and recreating the MV (which causes downtime), this feature follows a three-step process:

1. **Create Temporary MV**: Creates a new Materialized View with a temporary name using the updated SQL definition
2. **Atomic Swap**: Uses `ALTER MATERIALIZED VIEW {original} SWAP WITH {temp}` to atomically exchange the original and temporary MVs
3. **Conditional Cleanup**: Optionally drops the old MV (now using the temporary name) based on configuration

This ensures the original MV name remains available throughout the entire process, achieving true zero downtime updates.

### Views

For Views, the process follows the same three-step approach as Materialized Views:

1. **Create Temporary View**: Creates a new View with a temporary name using the updated SQL definition
2. **Atomic Swap**: Uses `ALTER VIEW {original} SWAP WITH {temp}` to atomically exchange the original and temporary Views
3. **Conditional Cleanup**: Optionally drops the old View (now using the temporary name) based on configuration

This approach uses RisingWave's `ALTER VIEW SWAP` syntax, which provides the same atomic swap semantics as materialized views, ensuring true zero downtime updates.

## Usage

### Enabling Zero Downtime Rebuilds

Zero downtime rebuilds require **two conditions** to be met:

1. **Model Configuration**: The model must be configured for zero downtime
2. **Runtime Flag**: The user must run dbt with `--vars 'zero_downtime: true'`

#### Step 1: Configure Your Model

Add zero downtime configuration to your model:

**For Materialized Views:**
```sql
-- models/my_mv_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

SELECT 
    id,
    name,
    created_at,
    updated_at  -- Adding new field
```

**For Views:**
```sql
-- models/my_view_model.sql
{{ config(
    materialized='view',
    zero_downtime={'enabled': true}
) }}

SELECT 
    id,
    name,
    created_at,
    updated_at  -- Adding new field
FROM {{ ref('source_table') }}
```

#### Step 2: Run with Zero Downtime Flag

```bash
# Enable zero downtime rebuild for configured models
dbt run --vars 'zero_downtime: true'

# Or target specific models
dbt run --models my_model --vars 'zero_downtime: true'
```

**Safety Note**: If you run `dbt run` without the `--vars 'zero_downtime: true'` flag, even models configured for zero downtime will use traditional rebuilds. This provides runtime control over when zero downtime rebuilds are used.

### Configuring Cleanup Behavior

By default, temporary MVs are **preserved** to avoid affecting downstream dependencies. You can control cleanup behavior in the model configuration:

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

-- Or simply (immediate_cleanup defaults to false)
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}
```

Then run with the zero downtime flag:

```bash
dbt run --vars 'zero_downtime: true'
```

### Different Behaviors Based on Configuration

| Model Config | Runtime Flag | Behavior |
|-------------|-------------|----------|
| `zero_downtime={'enabled': true}` | `--vars 'zero_downtime: true'` | **Zero downtime rebuild** |
| `zero_downtime={'enabled': true}` | No flag | **Traditional rebuild** (with helpful log message) |
| No zero downtime config | `--vars 'zero_downtime: true'` | **Traditional rebuild** |
| No zero downtime config | No flag | **Traditional rebuild** |

## Temporary Object Management

### Understanding the Cleanup Strategy

**Default Behavior (Recommended)**: Temporary objects (MVs and views) are preserved after swap to maintain downstream dependencies. This prevents CASCADE drops from affecting dependent objects, ensuring true zero downtime.

**Immediate Cleanup**: When enabled, temporary objects are dropped immediately after swap. This may affect downstream objects if they depend on the original object.

### Managing Temporary Objects with dbt Commands

#### Listing Temporary Objects

**Materialized Views:**
```bash
# List all temporary MVs across all schemas
dbt run-operation list_temp_mvs

# List temporary MVs in a specific schema
dbt run-operation list_temp_mvs --args '{"schema_name": "public"}'
```

**Views:**
```bash
# List all temporary views across all schemas
dbt run-operation list_temp_views

# List temporary views in a specific schema
dbt run-operation list_temp_views --args '{"schema_name": "public"}'
```

#### Cleaning Up Temporary Objects

**Materialized Views:**
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

**Views:**
```bash
# Dry run - see what would be cleaned up (safe to run)
dbt run-operation cleanup_temp_views --args '{"dry": true}'

# Dry run for specific schema
dbt run-operation cleanup_temp_views --args '{"schema_name": "public", "dry": true}'

# Actually clean up temporary views (caution: this will drop views)
dbt run-operation cleanup_temp_views

# Clean up temporary views in specific schema
dbt run-operation cleanup_temp_views --args '{"schema_name": "public"}'
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

Zero downtime rebuilds are triggered when **ALL** of the following conditions are met:

1. **Existing MV**: A Materialized View must already exist
2. **Non-full-refresh Mode**: Only applies when not using `--full-refresh`
3. **Model Configuration**: Model must have `zero_downtime={'enabled': true}` in config
4. **Runtime Flag**: Must be run with `--vars 'zero_downtime: true'`

## When Traditional Handling Is Used

The following scenarios will use traditional configuration change handling:

1. **Missing Model Config**: When model doesn't have `zero_downtime={'enabled': true}`
2. **Missing Runtime Flag**: When `--vars 'zero_downtime: true'` is not provided
3. **Full Refresh Mode**: When using the `--full-refresh` parameter
4. **Initial Creation**: When the MV doesn't exist (first-time creation)

## Technical Details

### Temporary Object Naming Convention

Both materialized views and views use temporary objects that follow the naming pattern: `{original_name}_dbt_zero_down_tmp_{timestamp}`

The timestamp format is an ISO format with UTC timezone, with special characters replaced by underscores for database compatibility.

Examples:
- `my_mv_model_dbt_zero_down_tmp_20231201T143022_123456Z` (for materialized views)
- `my_view_model_dbt_zero_down_tmp_20231201T143022_123456Z` (for views)

**Security Note**: The specific naming pattern `_dbt_zero_down_tmp_` is used to avoid conflicts with user-created tables that might contain generic patterns like `_tmp_`.

### Implementation Macros

The feature relies on several core macros for different materialization types:

#### Materialized View Macros
1. **`risingwave__create_materialized_view_with_temp_name`**: Generates SQL to create an MV with a temporary name
2. **`risingwave__swap_materialized_views`**: Generates SQL for the MV swap operation
3. **`risingwave__list_temp_materialized_views`**: Lists temporary MVs for cleanup management
4. **`risingwave__cleanup_temp_materialized_views`**: Utility for cleaning up temporary MVs

#### View Macros
1. **`risingwave__create_view_with_temp_name`**: Generates SQL to create a view with a temporary name
2. **`risingwave__swap_views`**: Generates SQL for the view swap operation
3. **`risingwave__list_temp_views`**: Lists temporary views for cleanup management
4. **`risingwave__cleanup_temp_views`**: Utility for cleaning up temporary views

### Execution Flow

#### Materialized Views
When zero downtime rebuild is enabled for materialized views, the following SQL operations are executed:

```sql
-- Step 1: Create temporary materialized view (main statement)
CREATE MATERIALIZED VIEW my_model_dbt_zero_down_tmp_20231201T143022_123456Z AS ...

-- Step 2: Swap the materialized views
ALTER MATERIALIZED VIEW my_model SWAP WITH my_model_dbt_zero_down_tmp_20231201T143022_123456Z

-- Step 3: Conditional cleanup (only if immediate_cleanup=true)
DROP MATERIALIZED VIEW IF EXISTS my_model_dbt_zero_down_tmp_20231201T143022_123456Z CASCADE
```

#### Views
When zero downtime rebuild is enabled for views, the following SQL operations are executed:

```sql
-- Step 1: Create temporary view (main statement)
CREATE VIEW my_view_dbt_zero_down_tmp_20231201T143022_123456Z AS ...

-- Step 2: Swap the views
ALTER VIEW my_view SWAP WITH my_view_dbt_zero_down_tmp_20231201T143022_123456Z

-- Step 3: Conditional cleanup (only if immediate_cleanup=true)
DROP VIEW IF EXISTS my_view_dbt_zero_down_tmp_20231201T143022_123456Z CASCADE
```

## Log Output

### Zero Downtime Rebuild

**Materialized Views:**
```
Using zero downtime rebuild with SWAP for materialized view update.
```

**Views:**
```
Using zero downtime rebuild with SWAP for view update.
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
-- models/users_model.sql
-- Safe approach: preserve downstream dependencies
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

SELECT id, name, email FROM users
```

Run with:
```bash
dbt run --models users_model --vars 'zero_downtime: true'
```

This preserves temporary MVs to protect downstream dependencies. Clean up manually when safe.

### Scenario 2: Immediate Cleanup (Use with Caution)

```sql
-- models/users_model.sql
-- Immediate cleanup: may affect downstream MVs
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}

SELECT id, name, email FROM users
```

Run with:
```bash
dbt run --models users_model --vars 'zero_downtime: true'
```

This immediately cleans up temporary MVs but may affect downstream dependencies.

### Scenario 3: Runtime Control

```sql
-- models/users_model.sql
-- Model is configured for zero downtime but won't use it unless flag is provided
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

SELECT id, name, email FROM users
```

```bash
# Traditional rebuild (even though model is configured for zero downtime)
dbt run --models users_model

# Zero downtime rebuild
dbt run --models users_model --vars 'zero_downtime: true'
```

This allows the same model to be deployed differently based on the situation.


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



## Configuration Reference

### Model Configuration Options

| Config Option | Default | Description |
|---------------|---------|-------------|
| `zero_downtime.enabled` | `false` | Enables the model for zero downtime rebuilds when set to `true` |
| `zero_downtime.immediate_cleanup` | `false` | Controls whether temporary objects (MVs/views) are immediately dropped after swap |

### Runtime Variable

| Variable Option | Default | Description |
|---------------|---------|-------------|
| `zero_downtime` | `false` | Runtime flag to trigger zero downtime rebuilds for configured models |

### Model Configuration Format

**Materialized Views:**
```sql
-- Minimal zero downtime configuration
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true}
) }}

-- With immediate cleanup
{{ config(
    materialized='materialized_view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}
```

**Views:**
```sql
-- Minimal zero downtime configuration for views
{{ config(
    materialized='view',
    zero_downtime={'enabled': true}
) }}

-- With immediate cleanup
{{ config(
    materialized='view',
    zero_downtime={'enabled': true, 'immediate_cleanup': true}
) }}
```

### Command Line Usage

```bash
# Enable zero downtime for models configured with zero_downtime={'enabled': true}
dbt run --vars 'zero_downtime: true'
```

## Limitations

### Core Limitations

- **RisingWave Version Requirements**: 
  - Materialized Views: Requires **RisingWave v2.2 or later** for `ALTER MATERIALIZED VIEW SWAP` syntax support
  - Views: Compatible with all RisingWave versions that support `CREATE OR REPLACE VIEW`
- **Materialization Compatibility**: 
  - Materialized Views: Only applicable to `materialized_view` materialization (not available for the deprecated `materializedview` materialization)
  - Views: Fully supported for `view` materialization
- **Full Refresh Incompatibility**: Not compatible with full refresh operations (`--full-refresh`)
- **Storage Requirements**: Requires additional storage capacity during rebuild process for temporary objects (both MVs and views)

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