# MoonGuard 项目申报说明

## 基本信息

- 项目名称：MoonGuard：MoonBit 原生 API 动态规则校验引擎
- 参赛者：gale
- 联系方式：wangjiale6036@gmail.com
- GitHub：https://github.com/wangjiale6036-dotcom/moon_guard
- 项目方向：API 动态规则校验引擎
- 项目性质：原创项目，非移植项目
- 开源许可证：Apache License 2.0

## 项目简介

MoonGuard 面向微服务、Serverless、边缘函数和配置中心中的动态校验需求。它允许开发者使用 MoonBit DSL 编写规则，也允许平台从 JSON 文档热加载规则，无须把每次业务策略变化都变成一次应用发版。引擎输出包含精确路径、稳定错误码、严重级别、规则名称和值预览的结构化报告，可直接被 HTTP API、日志系统和管理后台使用。

项目采用无回调的规则树和纯 MoonBit 核心实现，在 Wasm、Wasm GC、JavaScript、Native 四种后端上共享语义。解析深度、执行深度、规则访问量和错误数量均有预算限制，适合把外部提交的规则作为不可信输入处理。

## 已完成基础

- 4,500+ 行非测试 MoonBit 源码与 157 个自动化测试；
- 字符串、数字、数组、对象和 JSON 基础类型校验；
- allOf、anyOf、oneOf、noneOf、not、optional、nullable 组合；
- 基于路径、取值、类型和嵌套规则的条件谓词；
- JSON 动态规则导入、规范化导出和往返一致性检查；
- 必填字段、附加字段、字段依赖、互斥组和至少一个字段组；
- 18 种常用 API 字符串格式和安全通配符；
- JSON Pointer / 点路径错误、统计信息、fail-fast 与资源预算；
- 规则静态分析、良构检查、轮廓输出和优化；
- 批量、JSON 数组、JSON Lines 校验与错误直方图；
- 用户注册、订单和 Webhook 示例，以及两套命令行演示；
- 面向四种 MoonBit 后端的 GitHub Actions 持续集成。

## 黑客松期间计划

1. 增加带版本和摘要的规则注册表，支持原子发布、回滚与缓存；
2. 设计受控的自定义格式扩展接口，同时保持动态规则不可携带代码；
3. 增加 OpenAPI 参数到 MoonGuard 规则的适配器；
4. 为大批量 JSON Lines 增加流式校验和内存上限；
5. 建立跨后端性能基准与规则复杂度基准；
6. 提供 Web Playground，展示规则编辑、实时诊断和报告导出；
7. 完善 Mooncakes 发布、版本兼容矩阵和中文教程。

## 预期验收成果

- 可复用的 MoonBit 库、稳定 API 和公开版本；
- 可运行的动态规则 CLI 与 Web 演示；
- 不少于 200 个自动化测试，并保持四后端通过；
- OpenAPI 常用类型、格式和必填约束转换；
- 规则发布、回滚、批量校验和性能基准文档；
- 完整 README、架构说明、贡献指南和示例集。

## 原创与依赖说明

MoonGuard 为参赛者原创实现，没有复制 ELK 项目或其他校验库源码。运行时只使用 MoonBit Core 的 JSON、数学等标准能力；项目代码采用 Apache License 2.0。后续如引入第三方组件，将在 `THIRD_PARTY_NOTICES.md` 中记录来源、版本和许可证。
