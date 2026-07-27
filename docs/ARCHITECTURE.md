# MoonGuard 架构说明

## 设计目标

MoonGuard 的核心目标是让 API 校验规则成为可审查、可序列化、可热更新的数据，而不是散落在业务代码里的条件语句。实现遵循四个约束：

1. 规则树不保存函数回调，保证跨后端可执行和可序列化。
2. 动态规则默认不可信，解析和执行均有边界检查。
3. 错误是结构化数据，路径和代码保持稳定。
4. 核心只依赖 MoonBit 标准库，避免不同目标的依赖差异。

## 模块划分

```text
constructors.mbt ─┐
schema_json.mbt ──┼─> Rule / Predicate / Policy (types.mbt)
schema_encode.mbt ┘                   │
                                     ▼
formats.mbt + json_path.mbt ─────> engine.mbt
                                     │
                    ┌────────────────┼───────────────┐
                    ▼                ▼               ▼
              ValidationReport  rule_analysis   batch.mbt
                    │
                    ▼
              JSON / CLI / API
```

| 文件 | 职责 |
| --- | --- |
| `types.mbt` | 定义规则代数、策略、报告、统计和批次类型 |
| `constructors.mbt` | 提供类型安全的 MoonBit 规则 DSL 与运行选项 |
| `schema_json.mbt` | 把动态 JSON 文档解析为规则树并收集诊断 |
| `schema_encode.mbt` | 把规则树规范化编码为 JSON，支持往返检查 |
| `engine.mbt` | 预算受控的递归执行器、组合规则和结构化错误 |
| `formats.mbt` | 18 种无外部依赖的字符串格式与安全通配符 |
| `json_path.mbt` | JSON Pointer、点路径和值预览 |
| `rule_analysis.mbt` | 静态分析、良构检查、轮廓生成和规则优化 |
| `batch.mbt` | 批次、JSON 数组、JSON Lines 和错误直方图 |
| `samples.mbt` | 用户注册、订单、Webhook 三类完整规则示例 |

## 执行模型

`validate` 为每次运行创建隔离的校验上下文。上下文保存问题数组、统计计数、当前命名规则栈以及以下预算：

- `max_issues`：报告最多保留的问题数；
- `max_depth`：值与规则递归深度；
- `max_rule_visits`：一次运行可访问的规则节点数；
- `fail_fast`：出现首个阻塞错误后停止；
- `include_value_preview`：是否在错误中展示截断后的值；
- `include_warnings`：是否执行非阻塞警告规则。

达到预算后报告的 `stats.truncated` 会被标记，不会把“不完整结果”伪装成完整结果。

## 规则代数

`Rule` 是递归枚举，原子规则负责类型与约束，组合规则负责控制流：

- 原子：`Kind`、`StringMatches`、`NumberMatches`、`EqualsValue`、`InValues`；
- 容器：`ArrayMatches`、`ObjectMatches`；
- 组合：`AllOf`、`AnyOf`、`OneOf`、`NoneOf`、`NotRule`；
- 包装：`Nullable`、`Optional`、`Named`、`WarningRule`；
- 动态控制：`When` 与 `AtPath`。

分支规则在临时上下文中试运行，仅在需要时合并诊断，避免 `anyOf` 成功后泄漏失败分支的错误。

## 动态规则安全

动态解析器对结构和类型逐字段检查，并限制规则嵌套深度。执行器再次施加独立预算，形成“解析期 + 运行期”两层保护。通配符匹配采用动态规划，不使用可能引发灾难性回溯的正则表达式。

不支持的关键字不会被当作已实现能力；解析结果中的 `warnings` 可由规则发布流程作为门禁处理。

## 路径与稳定错误码

默认路径是 RFC 6901 风格的 JSON Pointer，属性名中的 `~` 和 `/` 会被转义。面向日志阅读时可以改为点路径。错误码按领域分组，例如：

- `type.string`、`type.object`
- `string.format`、`string.pattern`
- `number.minimum`、`number.multiple_of`
- `array.unique`、`array.contains`
- `object.required`、`object.additional`
- `logic.any_of`、`condition.failed`

调用方应依赖错误码和路径，不应解析人类可读消息。

## 扩展方式

新增约束需要完成四个闭环：

1. 在 `Rule` 或策略结构中增加明确类型；
2. 在动态解析和编码中实现对称映射；
3. 在执行器中生成稳定错误码；
4. 增加成功、失败、边界和四后端测试。

计划中的自定义格式注册表会采用显式、受控接口；动态 JSON 文档仍不会直接携带可执行代码。

## 版本策略

v0.x 阶段可能增加规则字段，但已有字段的含义不做静默改变。规则文档持久化时应记录项目版本，并在发布前运行 `parse_rule_document`、`rule_is_well_formed` 和 `rule_round_trip`。
