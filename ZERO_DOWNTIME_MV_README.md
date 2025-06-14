# Zero Downtime Materialized View Rebuild

## 概述

这个功能实现了零停机时间的 Materialized View (MV) 重建，利用 RisingWave 的 `ALTER MATERIALIZED VIEW SWAP` 语法来实现无缝切换。

## 工作原理

当 dbt 检测到 Materialized View 的定义发生变化时，不再直接删除旧的 MV 重建，而是采用以下步骤：

1. **创建临时 MV**: 使用新的 SQL 定义创建一个临时的 Materialized View（名称格式：`{original_name}_tmp_{timestamp}`）
2. **原子性交换**: 使用 `ALTER MATERIALIZED VIEW {original} SWAP {temp}` 语法交换原 MV 和临时 MV
3. **清理**: 删除旧的 MV（现在是临时名称）

这样可以确保在整个过程中，原 MV 名称始终可用，实现零停机时间的更新。

## 使用方法

### 默认行为

零停机时间重建功能默认启用。当你修改 Materialized View 的 SQL 定义并运行 `dbt run` 时，会自动使用零停机时间重建：

```sql
-- models/my_model.sql
{{ config(materialized='materialized_view') }}

SELECT 
    id,
    name,
    created_at,
    updated_at  -- 新增字段
FROM {{ ref('source_table') }}
```

### 手动配置

你也可以明确配置零停机时间模式：

```sql
-- models/my_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime=true
) }}

SELECT * FROM {{ ref('source_table') }}
```

### 禁用零停机时间重建

如果你想使用传统的 drop-and-create 方式，可以禁用零停机时间功能：

```sql
-- models/my_model.sql
{{ config(
    materialized='materialized_view',
    zero_downtime=false
) }}

SELECT * FROM {{ ref('source_table') }}
```

## 何时触发零停机时间重建

零停机时间重建会在以下情况触发：

1. **SQL 定义变更**: 当 Materialized View 的 SELECT 语句发生变化时
2. **配置变更**: 当相关配置发生变化时
3. **非 full_refresh 模式**: 只有在非 full refresh 模式下才会使用零停机时间重建

## 不适用的情况

以下情况仍会使用传统的 drop-and-create 方式：

1. **Full refresh 模式**: 使用 `--full-refresh` 参数时
2. **首次创建**: MV 不存在时的首次创建
3. **禁用零停机时间**: 明确设置 `zero_downtime=false` 时

## 技术细节

### 临时 MV 命名规则

临时 MV 的命名格式为：`{original_name}_tmp_{timestamp}`

其中 timestamp 格式为：`YYYYMMDD_HHMMSS_microseconds`

例如：`my_model_tmp_20231201_143022_123456`

### 新增的宏

1. **`risingwave__create_materialized_view_with_temp_name`**: 创建具有临时名称的 MV
2. **`risingwave__swap_materialized_views`**: 执行 MV 交换操作
3. **`risingwave__zero_downtime_materialized_view_rebuild`**: 完整的零停机时间重建流程

## 日志输出

当使用零停机时间重建时，会在日志中看到以下信息：

```
Detected changes to materialized view definition. Using zero downtime rebuild with SWAP.
```

## 错误处理

如果在零停机时间重建过程中发生错误：

1. **临时 MV 创建失败**: 会保留原 MV，不会影响现有服务
2. **SWAP 操作失败**: 会尝试清理临时 MV
3. **清理失败**: 可能需要手动清理遗留的临时 MV

## 与其他功能的兼容性

- ✅ **索引**: 支持在重建后重新创建索引
- ✅ **文档**: 支持文档持久化
- ✅ **钩子**: 支持 pre/post hooks
- ✅ **配置变更处理**: 与现有的配置变更处理机制兼容

## 性能考虑

- 零停机时间重建需要额外的存储空间来存储临时 MV
- 在高负载情况下，SWAP 操作可能会有短暂的性能影响
- 建议在低峰时段进行大型 MV 的重建

## 示例场景

### 场景 1: 添加新列

```sql
-- 原始定义
SELECT id, name FROM users

-- 修改后
SELECT id, name, email FROM users
```

使用零停机时间重建，用户查询不会中断。

### 场景 2: 修改聚合逻辑

```sql
-- 原始定义
SELECT 
    user_id, 
    COUNT(*) as order_count 
FROM orders 
GROUP BY user_id

-- 修改后
SELECT 
    user_id, 
    COUNT(*) as order_count,
    SUM(amount) as total_amount 
FROM orders 
GROUP BY user_id
```

使用零停机时间重建，依赖这个 MV 的下游查询不会失败。

## 最佳实践

1. **监控临时 MV**: 定期检查是否有遗留的临时 MV 需要清理
2. **存储空间**: 确保有足够的存储空间来支持临时 MV
3. **测试**: 在生产环境使用前，先在测试环境验证功能
4. **回滚计划**: 准备回滚计划以应对意外情况

## 故障排除

### 常见问题

1. **临时 MV 名称冲突**: 使用了微秒级时间戳，冲突概率极低
2. **权限问题**: 确保 dbt 用户有创建、删除和修改 MV 的权限
3. **存储空间不足**: 监控存储使用情况，确保有足够空间

### 调试技巧

1. 启用详细日志模式：`dbt run --log-level debug`
2. 检查 RisingWave 的日志来查看 SWAP 操作的详细信息
3. 使用 `dbt ls` 命令验证模型状态 