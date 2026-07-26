# Project memory

本文档保存跨模块、可复用且已经验证的项目事实，并作为专项文档的索引。事实保持被发现或确认时
使用的语言；不要为了统一语言而翻译。易变的验收状态、操作细节和架构说明留在对应专项文档中。

这里不是工作日志。不得写入聊天流水、完整命令输出、秘密值、私钥、OAuth token、prompt 或未经
验证的猜测。

## 文档索引

- [ChatGPT code-task app](docs/chatgpt-app.md)：控制面、OAuth、GitHub App 与部署配置。
- [ADR 0001](docs/adr/0001-oauth-kv-task-durable-objects.md)：OAuth KV 与 task Durable Object 的存储边界及重新评审条件。
- [ChatGPT app acceptance memory](docs/chatgpt-app-acceptance.md)：当前验收状态和未完成的外部验证。
- [Runner operations runbook](docs/runner-operations-runbook.md)：临时 runner 的操作与验证。
- [Lark session card](docs/lark-reporting.md)：Lark webhook、可更新卡片与连接信息。
- [Security](SECURITY.md)：凭证边界、威胁模型和安全检查表。

## 已验证事实

证据最近复核于 2026-07-26；条目中另有说明时以条目边界为准。

| 事实 | 证据与适用边界 | 对实现或验收的影响 |
| --- | --- | --- |
| `weavertech-group` 是 GitHub **User**，不是 Organization。 | 当前已认证 `gh` 会话调用 `GET /users/weavertech-group` 返回 `type: User`。这是证据日期时的账户类型；其他组织拥有的目标仓库仍可能需要组织审批。 | App 安装到这个 owner 时不存在 `weavertech-group` 组织审批 gate。 |
| 当前 `gh` 身份对 `weavertech-group/runner` 具有 admin、push 和 pull 权限。 | `GET /repos/weavertech-group/runner` 的三个权限标志均为 true，仅适用于当前本地认证会话。 | 当前会话能够管理仓库，但这不能证明 GitHub App installation 已获得所需权限。 |
| 一个 GitHub App 可以同时承担用户授权和 installation 身份，不需要额外创建传统 GitHub OAuth App。 | Worker 使用 GitHub App client credentials 完成 user-to-server authorization code exchange；`github.js` 使用 App JWT 创建 installation token。测试覆盖两条路径，并拒绝 `GITHUB_OAUTH_*` 配置。 | 保持一个 App registration，不引入传统 OAuth App 的宽泛 `repo` scope。 |
| GitHub App installation ID 属于具体 installation，可以通过 runner 仓库自动解析。 | `github.js` 先调用 `GET /repos/{owner}/{repo}/installation`，再使用返回的 ID 调用 `POST /app/installations/{id}/access_tokens`；production-edge test 验证了该请求序列。 | 不要求操作者复制或持久保存 installation ID。 |
| GitHub user access token 与 installation token 职责不同。 | 授权路径保存并刷新 user token，用于检查用户对目标仓库的访问权；workflow dispatch 使用短期 installation token。两条路径由不同测试覆盖。 | 两类凭证不能互相替代，也不能出现在 MCP 输出中。 |
| GitHub Actions 自定义 secret 名不能以 `GITHUB_` 开头。 | Repository secret API 对 `GITHUB_APP_ID` 返回 HTTP 422，并明确说明该前缀被保留；workflow 契约测试拒绝 `secrets.GITHUB_*`。 | Worker 可以继续使用 `GITHUB_APP_*` 绑定，但 runner repository 必须使用 `RUNNER_GITHUB_APP_ID` 与 `RUNNER_GITHUB_APP_PRIVATE_KEY`。 |
| 固定版本的 `openai/codex-action` 中，`allow-bots` 只信任 `github-actions[bot]`；自定义 GitHub App actor 必须通过 `allow-bot-users` 精确列出。 | 已检查当前固定 SHA 的 Action 权限判断源码，并通过 App JWT 确认当前 App slug；workflow 契约测试固定了对应的 `<app-slug>[bot]`。 | Worker 使用 App installation token dispatch workflow 时，不能只配置 `allow-bots: true`，否则 Codex 会在 actor 权限检查阶段被拒绝。 |
| Cloudflare user API token 与 account API token 使用不同的验证入口。 | 已验证并记录在 [ChatGPT code-task app](docs/chatgpt-app.md)：`cfut_` 使用 `/user/tokens/verify`，`cfat_` 使用 `/accounts/{account_id}/tokens/verify`。 | 错误 ownership endpoint 返回的 `401` 不能证明 token 无效；`active` 也不能证明 token 具备部署所需的全部权限。 |
| 当前本地 Cloudflare 部署只需要一个 `CLOUDFLARE_API_TOKEN`。 | Worker/KV 部署均使用 Wrangler 的标准 token 变量；仓库没有 Billing、D1、Access 或 route-profile API 调用，Cloudflare 也建议部署过程持续使用同一个具备所需权限的 token。 | `.secrets.env` 不按 Cloudflare API 拆分 token；`CLOUDFLARE_ACCOUNT_ID` 只是目标账户标识。自定义域名或新增 Cloudflare 产品时重新评审权限。 |
| OAuth 与 task 使用不同存储是有意的边界，不是为了统一技术栈而遗漏 D1。 | 当前 `@cloudflare/workers-oauth-provider` 要求 `OAUTH_KV`，并负责 token hash、grant props 加密、过期和撤销；task 则由每 task 一个 Durable Object 串行处理 callback、取消和结果更新。权衡记录在 [ADR 0001](docs/adr/0001-oauth-kv-task-durable-objects.md)。 | 当前不需要 D1 权限。只有出现立即全局撤销、关系型授权查询、完整审计报表，或上游提供事务型 storage adapter 时才重新评审。 |
| 本地 GitHub App 私钥文件 `*.private-key.pem` 已被忽略。 | `git check-ignore` 将本地私钥文件匹配到仓库 `.gitignore` 规则；未读取私钥内容。 | 私钥不得进入 tracked files、文档、日志、summary 或 artifact。 |
