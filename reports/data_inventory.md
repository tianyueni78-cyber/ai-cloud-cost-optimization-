# 原始数据盘点

## 1. 盘点目的

在数据审计和业务分析前，确认五张原始数据表的规模、行粒度、关键字段、时间字段、主要指标及表间关系。本报告只描述数据结构，不判断具体记录是否异常。

## 2. 数据规模

| 数据表 | 行数 | 字段数 | 一行代表什么 |
|---|---:|---:|---|
| `resource_inventory.csv` | 58 | 17 | 一个 GPU 资源池 |
| `resource_usage.csv` | 506,899 | 16 | 通常为一个资源池在一个 UTC 小时内的使用观测 |
| `cloud_billing.csv` | 1,209 | 16 | 一条账单费用记录 |
| `team_sla.csv` | 14 | 15 | 一条带生效期的 SLA 规则 |
| `business_events.csv` | 27 | 11 | 一项业务、技术或采购事件 |

`resource_usage.csv` 占据绝大部分数据量，正式检查和分析应使用 DuckDB 等能够直接查询大型 CSV 的工具，不建议依赖人工浏览完整文件。

## 3. 表级说明

### 3.1 资源清单 `resource_inventory.csv`

- 候选主键：`resource_pool_id`。
- 主要分类：`team_id`、`product_id`、`workload_type`、`gpu_model`、`region`、`procurement_model`。
- 主要数值：`gpu_count`、`hourly_list_price_usd`、`effective_hourly_rate_usd`。
- 生命周期：`start_date`、`end_date`。
- 合同与业务限制：`contract_id`、`failover_role`、`environment`。
- 用途：为使用记录和账单补充 GPU、区域、采购、归属与费率信息。

### 3.2 资源使用 `resource_usage.csv`

- 记录标识：`usage_record_id`。
- 业务重复候选键：`resource_pool_id` 与 `timestamp_utc`，实际规则需在审计中验证。
- 时间粒度：UTC 小时。
- 容量指标：`allocated_gpu_count`、`active_gpu_count`。
- 效率指标：`gpu_utilization_pct`、`memory_utilization_pct`。
- 业务量：`business_volume`，必须结合 `volume_unit` 解释。
- 服务表现：`p95_latency_ms`、`queue_time_seconds`、`availability_pct`。
- 数据质量背景：`telemetry_status`。
- 用途：分析资源使用、业务量、性能、SLA 和时间趋势。

### 3.3 云账单 `cloud_billing.csv`

- 候选主键：`billing_line_id`。
- 时间口径：`invoice_month`、`usage_start_date`、`usage_end_date`、`recorded_at`。
- 关联字段：`resource_pool_id`、`team_id`、`contract_id`。
- 费用分类：`charge_type`、`procurement_model`。
- 使用和价格：`billed_gpu_hours`、`unit_rate_usd`。
- 金额：`gross_cost_usd`、`discount_usd`、`net_cost_usd`。
- 用途：分析成本趋势、采购方式、跨月入账、抵扣和调整。

### 3.4 团队 SLA `team_sla.csv`

- 候选主键：`sla_id`。
- 适用范围：`team_id`、`product_id`、`workload_type`、`region`。
- 生效期间：`effective_from`、`effective_to`。
- 关键等级：`priority_tier`。
- 服务目标：`availability_target_pct`、`p95_latency_target_ms`、`max_queue_time_seconds`。
- 容量和恢复：`min_spare_capacity_pct`、`rto_minutes`、`interruptible_allowed`。
- 用途：判断实际服务表现、资源保留理由和优化边界。

### 3.5 业务事件 `business_events.csv`

- 候选主键：`event_id`。
- 事件范围：`team_id`、`product_id`、`region`。
- 事件期间：`start_timestamp_utc`、`end_timestamp_utc`。
- 事件分类：`event_type`、`severity`、`source_system`。
- 业务背景：`expected_impact`、`event_description`。
- 用途：为指标变化提供发布、客户、事故、迁移和采购背景。

## 4. 初步表关系

```text
resource_inventory
  ├── resource_pool_id ── resource_usage
  └── resource_pool_id ── cloud_billing

team_sla
  └── team_id + product_id + workload_type + region + 生效期间
      └── resource_usage / resource_inventory

business_events
  └── team_id + product_id + region + 事件期间
      └── resource_usage / cloud_billing

cloud_billing
  └── contract_id / team_id / resource_pool_id
      └── resource_inventory
```

同名字段不代表可以直接连接。正式 JOIN 前必须检查键格式、唯一性、空值、生效期间和 JOIN 后的行数变化。

## 5. 类型观察与待审计事项

- `timestamp_utc`、`recorded_at` 和事件时间被识别为带时区时间戳，符合 UTC 分析需要。
- `gpu_count`、业务量和 SLA 秒数被识别为整数；利用率、延迟和金额被识别为小数。
- `end_date` 和 `effective_to` 被推断为 `VARCHAR`。这可能与列中大量空值有关，需在审计阶段检查非空记录能否转换为日期。
- DuckDB 对 CSV 显示 `null = YES`，仅表示文件没有数据库非空约束，不代表字段实际存在空值。
- `business_volume` 不能脱离 `volume_unit` 汇总。
- 账单必须区分使用期间、发票月份和进入系统的记录时间。

## 6. 已完成的总量核对

- 资源清单包含 58 个资源池。
- `gpu_count` 汇总为 1,016 张 GPU。
- 按团队、GPU 型号、采购方式和工作负载分别汇总时，GPU 总数均能核对到 1,016。

以上核对只确认基础汇总一致，不代表数据质量审计已经完成。

## 7. 下一步

进入数据审计，按以下顺序检查：

1. 主键和业务键重复；
2. 必填字段空值；
3. 数值范围与枚举值；
4. ID 格式一致性；
5. 标准化前后关联率；
6. 时间范围和跨月记录；
7. 账单金额等式。
