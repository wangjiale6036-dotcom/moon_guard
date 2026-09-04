# Security Policy

## Supported versions

当前仅维护最新的 0.x 版本。

## Reporting a vulnerability

请不要在公开 Issue 中披露可利用细节。请通过 GitHub 仓库的私密漏洞报告功能提交复现步骤、受影响版本、规则或输入样本以及可能影响。维护者将在 7 天内确认收到报告。

## Untrusted rules

外部规则文档应被视为不可信输入。生产环境必须设置合理的 `max_depth`、`max_rule_visits` 和 `max_issues`，并在发布规则前检查解析警告。MoonGuard 的资源预算降低拒绝服务风险，但不能代替 API 网关的请求体大小、请求速率和执行超时限制。

## Shadow replay privacy

影子回放样本可能包含账号、令牌或其他敏感字段。`default_shadow_options` 默认关闭诊断中的值预览，`shadow_validate` 默认也不保存请求体。只有调用方显式设置 `capture_witnesses=true` 时，MoonGuard 才会为 `CandidateRegression` 和 `CandidateRelaxation` 保存规范 JSON 快照；稳定样本仍不会保存。

生产环境应优先提供脱敏、最小化且有保留期限的回放样本。导出或上传 `ShadowReport` 前应再次检查业务字段，不能把本库的默认脱敏当作完整的数据合规方案。
