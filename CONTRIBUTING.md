# Contributing to MoonGuard

感谢参与 MoonGuard。提交变更前请先创建 Issue，说明要解决的 API 校验场景、预期规则语义和跨后端影响。

## 本地检查

```bash
moon fmt
moon check --deny-warn --target all
moon test --deny-warn --target wasm
moon test --deny-warn --target wasm-gc
moon test --deny-warn --target js
moon test --deny-warn --target native
moon build --target all
```

每个新增规则至少应包含成功、失败和边界测试。修改动态 JSON 语法时，还必须同时更新解析、编码、往返测试、README 示例与架构文档。

## 兼容性原则

- 不静默改变已有关键字的含义；
- 错误码是公共契约，消息文字可以改进；
- 不为某个后端加入行为不同的快速路径；
- 动态规则不得携带任意可执行代码；
- 新增循环或递归逻辑时必须说明复杂度和预算行为。

提交信息使用简洁的祈使句。Pull Request 应说明动机、设计、测试结果和是否影响规则文档兼容性。
