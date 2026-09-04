# MoonGuard 兼容性雷达

MoonGuard 兼容性雷达用于在动态 API 规则升级前汇总三类证据：规则树的静态变化、同一批样本在两个版本上的行为差异，以及调用方配置的发布阈值。它帮助开发者发现潜在破坏、解释阻止晋级的原因，并选择要执行的规则版本。

它是一套发布辅助能力，不是任意规则关系的形式化证明器，也不负责采集生产流量、部署应用或操作网络网关。

## 判断方向

兼容性分析始终按“基线版本 -> 候选版本”的方向解释：

- `BreakingImpact`：候选规则可能拒绝基线规则原本接受的输入；
- `RelaxingImpact`：候选规则扩大了可接受输入范围，通常不破坏旧调用方，但可能放宽安全策略；
- `ReviewImpact`：仅凭当前规则树分析不能可靠决定，需要人工复核或样本回放。

静态报告中的 `backward_compatible=true` 仅表示当前实现没有发现 `BreakingImpact` 或 `ReviewImpact`。它是保守的发布门禁信号，不代表对所有可能输入完成了数学证明。`score` 是便于排序的启发式分数，也不是兼容率、概率或测试覆盖率。

## 工作流

```text
基线规则 + 候选规则 ──> 静态兼容性预检 ─┐
                                            ├─> 发布策略评估 ─> 阻止或晋级
调用方提供的样本 ──────> 双版本影子回放 ─┘

routing key ───────────> 确定性分桶 ──────> 选择本次校验使用的版本
```

推荐先发布候选修订但不激活，再依次执行静态比较、影子回放和策略评估。只有策略返回 `PromoteCandidate` 时，调用方才应激活候选版本。

## 静态兼容性预检

### 公开 API

- `compare_rules(previous, candidate)`：比较两个已经解析的 `Rule`；
- `compare_rule_json(baseline_json, candidate_json)`：解析并比较两份动态 JSON 规则；
- `compatibility_to_json(report)`：输出结构化 JSON；
- `RuleRegistry::compare_versions(channel, baseline_version, candidate_version)`：比较同一 channel 的两个已发布版本；
- `RuleRegistry::compare_with_active(channel, candidate_version)`：以当前激活版本为基线比较候选版本。

`compare_rule_json` 不会静默丢弃解析错误。其返回值 `CompatibilityParseResult` 会分别标记基线或候选规则的解析问题；任一规则不能解析时，不生成兼容性结论。

### 报告内容

`CompatibilityReport` 包含：

- `backward_compatible`：当前门禁结论；
- `score`：启发式分流分数；
- `breaking_count`、`relaxing_count`、`review_count`：三类变化计数；
- `changes`：带路径、关键字、影响类别和说明的 `RuleChange` 数组。

变化路径采用 JSON Pointer 风格，便于定位嵌套对象属性、数组元素规则和约束关键字。分析覆盖 MoonGuard 已实现的常用类型、字符串、数字、数组、对象、枚举、包装规则和部分组合规则。复杂条件、集合关系或不能可靠归约的规则形态会被保守处理为需要复核或潜在破坏。

```moonbit nocheck
let parsed = compare_rule_json(baseline_schema, candidate_schema)
match parsed.report {
  Some(report) => println(compatibility_to_json(report))
  None => println(parsed.errors.join("\n"))
}
```

静态预检只读取规则，不执行请求样本，也不修改注册表。

## 双版本影子回放

### 公开 API

- `default_shadow_options()`：返回适合影子回放的默认校验选项；
- `shadow_validate(baseline, candidate, cases)`：用两个规则校验同一批 `ValidationCase`；
- `shadow_to_json(report)`：输出结构化 JSON；
- `regression_witnesses(report)`：提取报告中已经观察到且允许保留的回归样本；
- `relaxation_witnesses(report)`：提取报告中已经观察到且允许保留的放宽样本；
- `RuleRegistry::shadow_versions(...)`：回放两个已发布版本；
- `RuleRegistry::shadow_with_active(...)`：以当前激活版本为基线回放候选版本。

影子回放把每个样本分为五类：

| 结果 | 含义 |
| --- | --- |
| `StableAccept` | 两个版本都接受 |
| `StableReject` | 两个版本都拒绝，且被比较的诊断字段一致 |
| `CandidateRegression` | 基线接受、候选拒绝 |
| `CandidateRelaxation` | 基线拒绝、候选接受 |
| `DiagnosticShift` | 两个版本都拒绝，但诊断路径、错误码、严重级别或问题数量/顺序发生变化 |

`DiagnosticShift` 当前比较问题数量和顺序，并比较每个问题的 `path`、`code` 与 `severity`；它不承诺比较所有人类可读消息或元数据。

`ShadowMetrics` 汇总样本总数、五类结果、双方通过数、被预算截断的样本数、问题直方图和回归基点。`regression_basis_points` 是本批样本中回归数除以样本总数后得到的整数基点，不是带置信区间的生产总体估计。

### 样本不是自动生成的反例

`regression_witnesses` 和 `relaxation_witnesses` 只返回调用方输入样本中已经观察到的行为差异。MoonGuard 当前不会从任意规则自动合成“最小反例”，也不会证明样本集覆盖了全部输入空间。

影子回放是纯计算操作，不会自动激活、回滚或删除任何规则版本。

## 发布策略

### 公开 API

- `default_rollout_policy()`：返回保守默认策略；
- `rollout_policy(...)`：创建带显式阈值的策略；
- `assess_rollout(static_report, shadow_report, policy)`：组合静态与样本证据；
- `rollout_assessment_to_json(assessment)`：输出结构化 JSON；
- `RuleRegistry::assess_candidate(...)`：比较当前激活版本与候选版本并评估；
- `RuleRegistry::promote_if_safe(...)`：仅在评估结果允许时激活候选版本。

`RolloutRecommendation` 有四种结果：

- `PromoteCandidate`：证据满足策略，可以晋级；
- `HoldCandidate`：存在静态复核项、规则放宽、诊断漂移、截断证据或其他策略不满足项；
- `RollbackCandidate`：样本中观察到的回归超过允许阈值；
- `InsufficientEvidence`：样本数不足。

这里的 `RollbackCandidate` 是建议类别。评估函数不会自动调用注册表回滚，也不会触发外部部署回滚。`promote_if_safe` 的唯一成功变更是把候选版本设为当前激活版本；其余建议均保持原激活指针不变。

### 保守默认策略

`default_rollout_policy()` 默认：

- 至少需要 100 个样本；
- 回归数量与回归基点上限均为 0；
- 放宽、诊断漂移和截断样本上限均为 0；
- 必须提供静态兼容性报告；
- 不允许跳过 `ReviewImpact`。

这些默认值适合演示严格门禁，但不是所有业务的通用上线标准。调用方应依据 API 风险等级、样本代表性和自身变更流程设置策略。

```moonbit nocheck
let assessment = registry.assess_candidate(
  "accounts",
  candidate_version,
  replay_cases,
)

let promotion = registry.promote_if_safe(
  "accounts",
  candidate_version,
  replay_cases,
)
```

评估原因保存在 `RolloutAssessment.reasons` 中，调用方不应只读取一个布尔值而忽略证据详情。

## 稳定分桶与候选规则校验

### 公开 API

- `stable_rollout_bucket(key, buckets=10000)`：把相同字符串稳定映射到同一分桶；
- `is_canary_selected(key, candidate_basis_points)`：按 0–10000 基点判断是否选择候选版本；
- `RuleRegistry::validate_canary_json(...)`：选择基线或候选规则并执行一次 JSON 校验。

分桶计算使用确定性、非加密算法，目的是让相同 routing key 在受支持后端获得一致选择。它不是密码哈希、身份匿名化或访问控制机制，也不保证小样本中得到完美均匀的比例。

`validate_canary_json` 只决定本次校验使用哪个规则版本：

- 不修改 channel 的激活版本；
- 不发送网络请求；
- 不接管 API 网关或负载均衡器；
- 不部署或停止任何应用实例。

调用方应选择稳定且不含敏感明文的 routing key，并自行处理真实请求路由、观测和故障恢复。

## 默认隐私行为

影子回放常使用脱敏日志或采样请求，因此 MoonGuard 采用以下默认值：

- `default_shadow_options()` 关闭 `ValidationIssue.value_preview`；
- `capture_witnesses` 默认为 `false`；
- 默认报告不保存请求体快照；
- 显式开启 `capture_witnesses=true` 后，也只为 `CandidateRegression` 和 `CandidateRelaxation` 保存序列化 JSON；稳定接受、稳定拒绝和诊断漂移不保存样本正文。

默认脱敏不等于完整的数据防泄漏方案。报告仍包含调用方提供的 case ID、错误路径、错误码和诊断信息；如果 case ID 自身含有账号或订单号，它仍可能属于敏感数据。显式捕获的样本也可能包含个人信息或密钥。

生产接入方仍需负责：

- 在进入 MoonGuard 前完成数据最小化和字段脱敏；
- 使用不直接暴露身份的 case ID 与 routing key；
- 限制报告访问权限和保留时间；
- 不把带样本正文的报告提交到公开仓库或普通 CI 日志；
- 按适用的数据合规要求处理回放数据。

## 安全不变量

以下约束是兼容性雷达发布流程的核心安全边界：

1. 比较方向固定为基线到候选，不能交换后继续复用原结论。
2. 规则解析失败时不产生兼容性报告，也不应进入发布评估。
3. 静态 `ReviewImpact` 默认阻止候选版本晋级。
4. 样本不足时默认返回 `InsufficientEvidence`，不会因为零回归而自动放行。
5. 被执行预算截断的报告不应被视为完整证据；默认策略不允许截断样本。
6. `shadow_validate` 与 `assess_rollout` 不修改注册表。
7. `promote_if_safe` 只有在建议为 `PromoteCandidate` 时才激活候选版本；失败路径保留原激活版本。
8. `validate_canary_json` 不修改激活指针，缺失 channel 或版本时显式返回 `found=false`。
9. 回归率采用整数基点计算，避免把跨后端浮点舍入差异带入策略边界。
10. 候选规则的放宽不等于无风险；默认策略会把观察到的放宽留给人工复核。

校验本身仍受 `ValidationOptions` 的最大问题数、最大递归深度和最大规则访问次数约束。影子回放默认继承这些预算，并额外关闭值预览。

## 能力边界

- 静态分析只覆盖 MoonGuard 规则模型，不是完整 JSON Schema、OpenAPI 或程序代码兼容性分析器。
- 静态结果采用结构化和保守规则，不能判定任意组合规则在所有输入上的集合关系。
- 样本回放质量取决于调用方提供数据的代表性；零观察回归不等于未来不会出现回归。
- 当前不计算统计置信区间，也不替调用方决定可接受的业务风险。
- 当前不自动生成测试样本或最小反例。
- 当前不采集线上流量，不持久化回放任务或指标，也不提供网络服务控制面。
- 规则注册表是进程内实现；manifest 可导出和恢复，但不是数据库事务、分布式一致性或多节点协调协议。
- 稳定分桶不是安全边界，不能用于鉴权、密钥派生或匿名化。
- MoonGuard 提供发布建议和规则选择原语，不负责自动部署、自动扩缩容或外部系统回滚。

## 推荐接入顺序

1. 将候选规则发布为未激活修订；
2. 使用 `compare_with_active` 获取静态变化，并逐项审查 `changes`；
3. 使用脱敏且有代表性的样本调用 `shadow_with_active`；
4. 检查回归、放宽、诊断漂移、截断和问题直方图；
5. 使用业务自定义 `RolloutPolicy` 调用 `assess_candidate`；
6. 仅在证据满足策略时调用 `promote_if_safe`；
7. 如需渐进验证，使用稳定分桶选择候选规则，但由外部系统负责真实流量治理；
8. 持续保留规则版本、策略、样本来源说明和评估报告，以便审计。

该流程旨在把“规则变更上线”从一次不可解释的布尔判断，变成可审查、可复现且边界清晰的工程决策。
