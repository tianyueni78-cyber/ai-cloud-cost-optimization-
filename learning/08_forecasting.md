# 08｜成本与容量预测

## 目标

预测未来 3 个月和 6 个月的业务量、GPU 需求与成本，并用情景而不是单一数字表达不确定性。

## 软件、输入和输出

- 软件：VS Code、Jupyter、Python、Pandas、Matplotlib。
- 输入：清洗并归因后的月度分析表。
- Notebook：`notebooks/03_forecasting.ipynb`。
- 输出：基准、低增长和高增长三种情景及回测指标。

## 操作顺序

```text
确定预测对象
→ 建立固定时间粒度
→ 绘制历史趋势
→ 划分训练与验证期间
→ 建立简单基线
→ 回测和计算误差
→ 加入业务情景
→ 转换为 GPU 与成本需求
→ 记录假设和风险
```

## A. 确定预测对象

不要直接预测所有原始行。先决定：

- 按月还是按周；
- 公司、产品还是团队；
- 业务量、活跃 GPU 小时还是成本；
- `volume_unit` 是否可比较。

作品集建议先做月度产品/负载预测，再汇总到公司层面。

## B. 用 Pandas 读取月度表

```python
import pandas as pd

monthly = pd.read_parquet("outputs/analysis/monthly_product_metrics.parquet")
monthly["month"] = pd.to_datetime(monthly["month"])
monthly = monthly.sort_values(["product_id", "workload_type", "month"])
monthly.head()
```

## C. 画出历史数据

```python
import matplotlib.pyplot as plt

series = monthly.query(
    "product_id == 'PRD-CONV' and volume_unit == 'requests'"
).set_index("month")["business_volume"]

series.plot(figsize=(10, 4), title="Monthly business volume")
plt.show()
```

先观察趋势、周期、断点和事件窗口，再选择方法。

## D. 按时间划分训练与验证

```python
train = series.iloc[:-3]
valid = series.iloc[-3:]
```

不能随机拆分时间序列，因为那会让模型看到未来信息。

## E. 建立简单基线

### 上月值基线

```python
baseline = valid.shift(1)
baseline.iloc[0] = train.iloc[-1]
```

### 平均增长率基线

```python
growth = train.pct_change().dropna().median()
forecast = []
value = train.iloc[-1]
for _ in range(len(valid)):
    value *= 1 + growth
    forecast.append(value)
```

简单基线不是“低级”，而是判断复杂模型是否真正增加价值的标准。

## F. 计算误差

```python
import numpy as np

mae = np.mean(np.abs(valid.to_numpy() - np.array(forecast)))
mape = np.mean(
    np.abs((valid.to_numpy() - np.array(forecast)) / valid.to_numpy())
)
```

分母可能为零时不要使用普通 MAPE；应选择 MAE、加权误差或安全处理。

## G. 建立三种情景

不要把“高增长”写成随意增加 20%。每个情景都要说明依据：

| 情景 | 依据 |
|---|---|
| 低增长 | 客户上线延迟、迁移推迟或宏观需求下降 |
| 基准 | 历史趋势和已知事件按计划发生 |
| 高增长 | 客户提前上线、活动放大或新产品采用超预期 |

## H. 从业务量转成容量和成本

需要估计：

```text
单位业务量所需 GPU 小时
目标利用率和备用容量
GPU 型号性能差异
采购方式费率
已签合同与新增容量
```

不要假设业务量增长 10%，成本必然增长 10%。利用率、型号和采购方式会改变关系。

## I. 输出预测表

至少包含：

- 预测月份；
- 产品和负载；
- 情景；
- 业务量；
- GPU 小时；
- 预计成本；
- 容量缺口；
- 主要假设。

## 知识树

```text
预测
├── 时间粒度
├── 趋势和事件
├── 时间切分
├── 简单基线
├── MAE / MAPE
├── 情景假设
├── 业务量到容量
└── 容量到成本
```

## 验收标准

- 没有随机拆分时间序列。
- 至少有一个简单基线和回测结果。
- 三种情景的假设明确。
- 预测业务量、容量和成本之间的转换可解释。
- 输出包含不确定性和限制。

## 建议提交

```powershell
git add notebooks/03_forecasting.ipynb
git commit -m "forecast: add validated cost and capacity scenarios"
git push
```
