# MoonGuard

MoonGuard 是一个使用 MoonBit 原生实现的**可解释 API 契约演化与动态规则校验引擎**。业务规则既可以在代码中组合，也可以从 JSON 文档在运行时加载；同一套规则可在 Wasm、Wasm GC、JavaScript 和 Native 后端执行。

本项目面向“2026 MoonBit 国产基础软件生态开源大赛—8 月黑客松”中建议的 **API 动态规则校验引擎**方向，是独立原创项目，不是 ELK 或其他项目的移植。

## 项目状态

- 7,526 行非测试 MoonBit 源码（含 CLI，按物理行统计）
- 310 个自动化测试，其中 110 个为 v0.3 Compatibility Radar 专项测试
- 4 种 MoonBit 后端持续集成
- 18 种内置字符串格式
- 静态兼容性预检、双版本影子回放、策略评估与稳定候选分桶
- 可发布、激活、回滚和持久化的进程内规则注册表
- Apache-2.0 开源许可证

## 为什么需要 MoonGuard

API 参数校验常被散落在路由、控制器和业务函数中。每次规则变更都要重新编译和部署，错误信息也难以保持一致。MoonGuard 把校验抽象为无回调的规则树：规则可以序列化、审查、缓存和热更新，并输出稳定的结构化诊断结果。

```text
JSON Schema / MoonBit DSL
            │
            ▼
      Rule 规则树 ─── 静态分析 / 优化 / 导出
            │
      ┌─────┴───────────────┐
      ▼                     ▼
 校验执行器             Compatibility Radar
      │              静态预检 + 影子回放 + 策略
      ▼                     │
ValidationReport            ▼
 JSON Pointer        候选晋级 / 保留 / 回退建议
```

## 核心能力

| 模块 | 能力 |
| --- | --- |
| 动态规则 | 从 JSON 解析规则，提供明确的解析错误和警告 |
| 版本治理 | 规则注册、兼容性门禁、激活、回滚、manifest 持久化 |
| 兼容性雷达 | 规则树结构化差异、影响等级、精确路径与解释 |
| 影子回放 | 双版本行为比较、5 类结果、回归基点、问题直方图、可选见证 |
| 安全灰度 | 显式发布策略、预期基线晋级、万分比稳定候选分桶 |
| 类型与取值 | null、boolean、integer、number、string、array、object、const、enum |
| 字符串 | 长度、前后缀、包含、通配符、白名单、黑名单、ASCII、非空白、格式 |
| 数字 | 开闭区间、倍数、整数、正数、负数、非零 |
| 数组 | 元素规则、元组前缀、长度、去重、contains 计数 |
| 对象 | 必填/可选/弃用字段、附加字段、依赖、互斥组、至少一个字段组 |
| 逻辑组合 | allOf、anyOf、oneOf、noneOf、not、nullable、optional |
| 条件规则 | exists、missing、equals、kind、validates 及布尔组合 |
| 安全预算 | 最大错误数、最大深度、规则访问量、fail-fast、值预览开关 |
| 工具链 | 规则静态分析、轮廓输出、规范化优化、JSON 往返、批量与 JSON Lines |

## 快速开始

```bash
git clone https://github.com/wangjiale6036-dotcom/moon_guard.git
cd moon_guard
moon test
moon run cmd/main
moon run cmd/schema
moon run cmd/registry
moon run cmd/radar
```

四个命令依次演示代码式规则、运行时 JSON 规则、版本注册表，以及“静态预检 → 影子回放 → 策略建议 → 阻止不安全晋级 → 稳定候选分桶”的 Compatibility Radar 流程。

## MoonBit 规则 DSL

```moonbit nocheck
let user_rule = strict_object([
  property("id", string_rule(format=Some("uuid"))),
  property("email", string_rule(format=Some("email"))),
  property(
    "age",
    number_rule(minimum=Some(13.0), maximum=Some(150.0), integer_only=true),
  ),
  optional_property(
    "roles",
    array_rule(
      items=Some(one_of_strings(["user", "editor", "admin"])),
      min_items=Some(1),
      unique_items=true,
    ),
  ),
])

let report = validate_json(user_rule, request_body)
if !report.valid {
  println(report_to_json(report))
}
```

构造器不依赖运行时回调，因此规则在四种后端上具有相同语义，也能安全地编码回 JSON。

## 动态 JSON 规则

`examples/user.schema.json` 是一份可直接加载的规则：

```json
{
  "$name": "user-registration",
  "type": "object",
  "additionalProperties": false,
  "required": ["id", "email", "age"],
  "properties": {
    "id": { "type": "string", "format": "uuid" },
    "email": { "type": "string", "format": "email", "maxLength": 254 },
    "age": { "type": "integer", "minimum": 13, "maximum": 150 },
    "roles": {
      "type": "array",
      "items": { "enum": ["user", "editor", "admin"] },
      "uniqueItems": true
    }
  }
}
```

```moonbit nocheck
match rule_from_json(schema_text) {
  Some(rule) => println(report_to_json(validate_json(rule, payload_text)))
  None => println("invalid rule document")
}
```

如需完整解析诊断，使用 `parse_rule_document`；它会返回规则、错误和非阻塞警告。

## 版本化规则注册表 MVP

规则注册表把动态校验从单次函数调用扩展为可运行的发布流程：

- 同一业务 channel 保存不可变的顺序版本；
- 首个版本自动激活，后续版本需要显式激活；
- 重复规则不会产生无意义的新版本；
- 兼容性样例全部通过后才会原子发布候选版本；
- 每次校验结果记录实际使用的 channel 和版本；
- 支持前一版本回滚、批量校验以及 JSON manifest 导出和恢复。

```moonbit nocheck
let registry = new_rule_registry()
let gate = registry.publish_json_checked(
  "accounts",
  schema_text,
  compatibility_cases,
  note="require account age",
  published_by="gale",
)

if gate.published {
  ignore(registry.activate("accounts", gate.result.version.unwrap()))
  let result = registry.validate_active_json("accounts", request_body)
  println(result.to_json().stringify(indent=2))
}

let backup = registry.manifest_json()
let restored = rule_registry_from_manifest(backup)
```

`cmd/registry` 提供上述链路的可运行演示。manifest 恢复采用事务语义：格式版本、规则 JSON、版本顺序或激活指针任一无效时，整个恢复操作失败，不暴露半成品注册表。

## Compatibility Radar：契约演化与安全灰度

仅验证候选规则“能跑”并不足以回答它是否会破坏已上线调用方。MoonGuard v0.3 把候选规则上线拆成三类证据：

1. `compare_rules` / `compare_with_active` 对规则树执行保守的结构化兼容性预检；
2. `shadow_validate` / `shadow_with_active` 对调用方提供的样本进行双版本回放；
3. `assess_rollout` 把静态与行为证据代入策略，`promote_if_safe` 仅在满足策略时激活候选。

```moonbit nocheck
///|
let static_result = registry.compare_with_active("accounts", candidate_version)

///|
let shadow = registry.shadow_with_active(
  "accounts",
  candidate_version,
  replay_cases,
  capture_witnesses=true,
)

///|
let assessment = registry.assess_candidate(
  "accounts",
  candidate_version,
  replay_cases,
  policy=rollout_policy(min_samples=100),
)

///|
let promoted = registry.promote_if_safe(
  "accounts",
  candidate_version,
  replay_cases,
  policy=rollout_policy(min_samples=100),
)
```

静态变化分为 `BreakingImpact`、`RelaxingImpact` 和 `ReviewImpact`。输出包含 JSON Pointer 路径、关键字和可读原因；遇到复杂条件、否定或互斥组合时会保守进入 Review，核心原则是“未知不能被静默判为兼容”。`score` 是人工分诊用的启发式分数，不是兼容率。

影子回放把结果分为 `StableAccept`、`StableReject`、`CandidateRegression`、`CandidateRelaxation`、`DiagnosticShift`。默认策略至少要求 100 个样本，并且不容忍已观察回归、静态或动态放宽、诊断漂移和截断证据。默认影子选项关闭值预览，也不保存请求体；只有显式启用 `capture_witnesses` 时，才会保存发生接受行为变化的样本快照。

`stable_rollout_bucket` 与 `validate_canary_json` 提供跨后端一致的 0–10000 基点候选规则选择。同一 routing key 会稳定命中同一版本；该能力是规则校验辅助，不负责真实网络分流或应用部署。

完整判定边界、安全不变量和 API 流程见 [docs/COMPATIBILITY_RADAR.md](docs/COMPATIBILITY_RADAR.md)。

## 结构化错误

MoonGuard 不只返回 true/false。每个问题都包含路径、机器可读代码、规则关键字、消息、严重级别、规则名称和值预览；报告同时记录规则访问次数、校验值数量、最大深度和截断状态。

```json
{
  "valid": false,
  "issues": [
    {
      "path": "/email",
      "code": "string.format",
      "keyword": "format",
      "message": "string is not a valid email",
      "severity": "Error",
      "rule_name": "user-registration",
      "value_preview": "\"not-an-email\""
    }
  ]
}
```

默认路径采用 JSON Pointer，也可通过 `with_path_style("dot")` 切换为点路径。

## 内置格式

`email`、`hostname`、`ipv4`、`ipv4-cidr`、`uuid`、`date`、`time`、`date-time`、`uri`、`semver`、`identifier`、`slug`、`base64`、`base64url`、`jwt`、`hex`、`mac`、`credit-card`。

格式实现采取无正则、无外部依赖的可移植算法；未知格式会被拒绝，避免拼写错误静默绕过校验。

## 批量校验

- `validate_batch`：校验带业务 ID 的内存值数组
- `validate_json_array`：把一个 JSON 数组作为批次处理
- `validate_json_lines`：逐行校验 JSON Lines
- `batch_issue_histogram`：按错误代码聚合计数
- `batch_to_json` / `batch_summary`：机器输出与人类摘要

## 规则治理

动态规则在上线前可使用：

- `analyze_rule`：统计节点、深度、属性、条件和命名规则
- `rule_outline`：生成便于代码评审的文本轮廓
- `rule_is_well_formed`：检测无效边界和危险结构
- `optimize_rule`：扁平化组合、消除重复包装和恒真规则
- `rule_to_json` / `rule_round_trip`：持久化和兼容性验证

## 开发与验证

```bash
moon fmt --check
moon check --deny-warn --target all
moon test --deny-warn --target wasm
moon test --deny-warn --target wasm-gc
moon test --deny-warn --target js
moon test --deny-warn --target native
moon build --target all
```

CI 对四个目标分别执行格式检查、类型检查、测试和构建。架构与扩展点见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，参赛项目说明见 [docs/PROJECT_APPLICATION.md](docs/PROJECT_APPLICATION.md)。

## 当前边界

MoonGuard v0.3.0 聚焦 JSON/API 请求体、配置数据校验、契约演化预检和进程内规则治理。静态报告不是形式化等价证明；影子数据由调用方提供；稳定分桶不操作网关或部署平台。项目不是完整的 JSON Schema 2020-12 实现，也不是网络化配置中心；当前不处理远程 `$ref`、正则表达式或 XML。显式的能力边界让运行成本和跨后端行为更容易预测。

## 许可证

Copyright 2026 gale. Licensed under the Apache License 2.0.
