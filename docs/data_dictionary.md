# 数据字典与业务规则

## 1. 通用约定

- 文件采用 UTF-8 编码和逗号分隔格式，首行为字段名。
- 金额统一为美元（USD）；时间戳采用 UTC ISO 8601 格式；日期采用 `YYYY-MM-DD`。
- 百分比字段使用 0–100 的数值。空字符串表示源系统未提供，不等同于 0。
- ID 来自多个系统，大小写、连字符和前后空格可能不一致；不提供预先清洗后的统一键。
- 重复、缺失和延迟记录属于原始数据的一部分，不应在导入阶段被静默删除。

## 2. `resource_inventory.csv`

每行代表一个可独立管理和计费的 GPU 资源池。

| 字段 | 类型 | 单位/格式 | 允许为空 | 含义 |
|---|---|---|---|---|
| `resource_pool_id` | text | ID | 否 | 资源池主标识 |
| `team_id` | text | ID | 否 | 主要责任团队 |
| `product_id` | text | ID | 否 | 主要服务产品；共享资源使用 `PRD-SHARED` |
| `workload_type` | text | 枚举 | 否 | `Training`、`Inference` 或 `Batch` |
| `gpu_model` | text | 枚举 | 否 | GPU 型号与显存版本 |
| `gpu_count` | integer | GPU 张数 | 否 | 资源池可用 GPU 总数 |
| `region` | text | 云区域 | 否 | 资源所在区域 |
| `cloud_provider` | text | 枚举 | 否 | 模拟云厂商代码 |
| `procurement_model` | text | 枚举 | 否 | `Owned`、`Reserved`、`SavingsPlan` 或 `OnDemand` |
| `contract_id` | text | ID | 是 | Reserved 或 Savings Plan 合同 |
| `start_date` | date | 日期 | 否 | 资源进入可用状态的日期 |
| `end_date` | date | 日期 | 是 | 资源退出日期；观察期内仍有效则为空 |
| `hourly_list_price_usd` | decimal | USD/GPU 小时 | 否 | 对应 GPU 和区域的参考按需单价 |
| `effective_hourly_rate_usd` | decimal | USD/GPU 小时 | 否 | 当前采购方式的有效小时成本 |
| `failover_role` | text | 枚举 | 否 | `Primary`、`WarmStandby`、`DR` 或 `None` |
| `environment` | text | 枚举 | 否 | `Production`、`Research` 或 `Development` |
| `cost_center` | text | ID | 否 | 财务成本中心 |

## 3. `resource_usage.csv`

正常情况下，每行代表一个资源池在一个 UTC 小时内的汇总观测。源系统重试可能产生重复记录。

| 字段 | 类型 | 单位/格式 | 允许为空 | 含义 |
|---|---|---|---|---|
| `usage_record_id` | text | ID | 否 | 使用记录标识；近似重复可能具有不同 ID |
| `timestamp_utc` | timestamp | UTC | 否 | 小时开始时间 |
| `resource_pool_id` | text | ID | 否 | 资源池标识，可能存在格式差异 |
| `team_id` | text | ID | 否 | 遥测系统记录的责任团队 |
| `product_id` | text | ID | 否 | 遥测系统记录的产品 |
| `workload_type` | text | 枚举 | 否 | `Training`、`Inference` 或 `Batch` |
| `allocated_gpu_count` | integer | GPU 张数 | 否 | 该小时已分配 GPU 数 |
| `active_gpu_count` | decimal | GPU 小时 | 是 | 实际活跃 GPU 的等效数量 |
| `gpu_utilization_pct` | decimal | % | 是 | GPU 核心平均利用率 |
| `memory_utilization_pct` | decimal | % | 是 | GPU 显存平均利用率 |
| `business_volume` | integer | 见单位字段 | 否 | 请求、作业或千页数量 |
| `volume_unit` | text | 枚举 | 否 | `requests`、`jobs` 或 `k_pages` |
| `p95_latency_ms` | decimal | 毫秒 | 是 | 推理 P95 延迟；非在线负载允许为空 |
| `queue_time_seconds` | decimal | 秒 | 是 | 训练或批处理等待时间；在线推理允许为空 |
| `availability_pct` | decimal | % | 是 | 该小时服务可用性 |
| `telemetry_status` | text | 枚举 | 否 | `complete`、`partial` 或 `late` |

`business_volume` 只能在相同 `volume_unit` 和可比较负载范围内汇总，不能把请求数、训练作业数和千页数直接相加。

## 4. `cloud_billing.csv`

每行代表账单系统中的一条费用记录，同一资源池和使用月份可以对应多条记录。

| 字段 | 类型 | 单位/格式 | 允许为空 | 含义 |
|---|---|---|---|---|
| `billing_line_id` | text | ID | 否 | 账单行标识 |
| `invoice_month` | text | `YYYY-MM` | 否 | 费用出现的发票月份 |
| `usage_start_date` | date | 日期 | 否 | 费用覆盖期间开始日 |
| `usage_end_date` | date | 日期 | 否 | 费用覆盖期间结束日，含当日 |
| `resource_pool_id` | text | ID | 是 | 可归属资源池；共享支持费用可能为空 |
| `team_id` | text | ID | 是 | 供应商标签团队；标签缺失时为空 |
| `contract_id` | text | ID | 是 | 对应采购承诺合同 |
| `charge_type` | text | 枚举 | 否 | `Usage`、`Commitment`、`UnusedCommitment`、`Credit`、`Adjustment` 或 `Support` |
| `procurement_model` | text | 枚举 | 否 | 产生费用时采用的采购方式 |
| `billed_gpu_hours` | decimal | GPU 小时 | 是 | 计费 GPU 小时；非用量费用允许为空 |
| `unit_rate_usd` | decimal | USD/GPU 小时 | 是 | 计费单价；支持费等允许为空 |
| `gross_cost_usd` | decimal | USD | 否 | 抵扣和调整前金额，可为负数 |
| `discount_usd` | decimal | USD | 否 | 合同或计划折扣，通常为非负数 |
| `net_cost_usd` | decimal | USD | 否 | `gross_cost_usd - discount_usd` |
| `currency` | text | ISO 代码 | 否 | 固定为 `USD` |
| `recorded_at` | timestamp | UTC | 否 | 账单行进入内部系统的时间 |

### 计费规则

- `Usage` 按实际计费 GPU 小时和费率计算。
- `Commitment` 是承诺采购的固定期间费用，不因实际利用率自动减少。
- `UnusedCommitment` 是内部管理口径，用于呈现未被工作负载覆盖的承诺成本；不应与承诺费用重复计入总账。
- `Credit` 为供应商抵扣或服务补偿，金额为负。
- `Adjustment` 包括价格修正、标签更正或延迟入账，可正可负。
- `Support` 是按月分配的云支持费用，可能只带团队标签而不带资源池。
- 发票月份可以晚于使用月份，金额汇总可能因逐行舍入出现小额差异。

## 5. `team_sla.csv`

每行代表一条带生效期的服务等级规则。

| 字段 | 类型 | 单位/格式 | 允许为空 | 含义 |
|---|---|---|---|---|
| `sla_id` | text | ID | 否 | SLA 规则标识 |
| `team_id` | text | ID | 否 | 责任团队 |
| `product_id` | text | ID | 否 | 适用产品 |
| `workload_type` | text | 枚举 | 否 | 适用负载类型 |
| `region` | text | 云区域 | 否 | 适用区域 |
| `effective_from` | date | 日期 | 否 | 规则生效日期 |
| `effective_to` | date | 日期 | 是 | 规则结束日期；仍有效则为空 |
| `priority_tier` | text | 枚举 | 否 | `P0`、`P1`、`P2` 或 `P3` |
| `availability_target_pct` | decimal | % | 是 | 月度可用性目标；训练允许为空 |
| `p95_latency_target_ms` | integer | 毫秒 | 是 | 在线推理延迟目标 |
| `max_queue_time_seconds` | integer | 秒 | 是 | 训练或批处理最大排队时间 |
| `min_spare_capacity_pct` | decimal | % | 否 | 最低备用容量比例 |
| `rto_minutes` | integer | 分钟 | 是 | 恢复时间目标 |
| `interruptible_allowed` | boolean | `true/false` | 否 | 是否允许中断任务 |
| `business_owner` | text | 姓名/职务 | 否 | SLA 业务责任人 |

## 6. `business_events.csv`

每行代表一项当时可记录的业务、技术或采购事件。

| 字段 | 类型 | 单位/格式 | 允许为空 | 含义 |
|---|---|---|---|---|
| `event_id` | text | ID | 否 | 事件标识 |
| `event_type` | text | 枚举 | 否 | `Launch`、`Customer`、`Campaign`、`TrainingRun`、`Incident`、`Migration`、`Procurement`、`Pricing` 或 `Capacity` |
| `start_timestamp_utc` | timestamp | UTC | 否 | 事件开始时间 |
| `end_timestamp_utc` | timestamp | UTC | 是 | 事件结束时间；持续影响时可为空 |
| `team_id` | text | ID | 是 | 主要关联团队 |
| `product_id` | text | ID | 是 | 主要关联产品 |
| `region` | text | 云区域 | 是 | 主要影响区域 |
| `severity` | text | 枚举 | 否 | `info`、`low`、`medium`、`high` 或 `critical` |
| `expected_impact` | text | 描述 | 是 | 事件发生时记录的预期影响 |
| `event_description` | text | 描述 | 否 | 不包含分析结论的事件说明 |
| `source_system` | text | 枚举 | 否 | 事件来源系统 |

事件记录描述业务上下文，而不是异常标签。事件与指标变化之间可能存在提前、滞后、范围不完全一致或没有显著影响的情况。

## 7. SLA 解释规则

- `P0`：直接影响核心付费客户或合规要求，通常需要最高可用性和快速恢复。
- `P1`：重要生产服务，允许有限降级，但不能长时间中断。
- `P2`：非实时或内部关键任务，可接受排队和计划性调整。
- `P3`：研究或开发任务，可中断且通常没有在线可用性目标。
- SLA 应按事件时间与生效日期连接，不能只取最新一行。
- 同一团队在不同产品、区域或工作负载上的 SLA 可能不同。

## 8. 已知业务限制

- 部分亚太客户要求数据留在 `ap-southeast-1`。
- `P0` 在线服务不能完全依赖单一区域或单一按需容量来源。
- 部分训练任务可延期，但模型发布日期和客户承诺会限制延期窗口。
- Reserved 和 Savings Plan 在合同到期前不能无成本取消。
- GPU 型号不能仅按张数等价替换；性能、显存和软件兼容性均可能不同。
- 共享平台费用需要采用明确且可解释的分摊驱动因素。
- 优化建议必须同时说明节省额、实施时间、SLA 影响和容量风险。
