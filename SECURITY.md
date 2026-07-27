# Security Policy

## Supported versions

当前仅维护最新的 0.x 版本。

## Reporting a vulnerability

请不要在公开 Issue 中披露可利用细节。请通过 GitHub 仓库的私密漏洞报告功能提交复现步骤、受影响版本、规则或输入样本以及可能影响。维护者将在 7 天内确认收到报告。

## Untrusted rules

外部规则文档应被视为不可信输入。生产环境必须设置合理的 `max_depth`、`max_rule_visits` 和 `max_issues`，并在发布规则前检查解析警告。MoonGuard 的资源预算降低拒绝服务风险，但不能代替 API 网关的请求体大小、请求速率和执行超时限制。
