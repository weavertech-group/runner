# 安全审查记录：2026-07-20

## 审查范围

本次审查覆盖：

```text
.github/workflows/private-runner-session.yml
.github/CODEOWNERS
.github/target-repositories.txt
scripts/*.sh
headscale/*.example.*
docs/*.md
tests/*.sh
.gitignore
```

同时核对了 DevSpace 的权限模型、Cloudflare Quick Tunnel 的生命周期，以及 GitHub Actions 对 fork、Secrets、Environments 和 CODEOWNERS 的边界。

## 总体结论

未发现“第三方仅通过 fork 本仓库即可读取上游 Secrets、加入上游 Headscale 或访问目标私有仓库”的路径。

当前 workflow 只通过人工 `workflow_dispatch` 启动，不会自动执行 fork pull request 中的代码。Fork 不继承上游 Secrets、Environments、Environment 审批规则、分支保护或 Headscale 配置。

项目不能仅靠源码被判定为完全安全。以下关键控制位于 GitHub 和 Headscale 管理平面，必须由管理员单独确认：

- 默认分支 ruleset/branch protection；
- Require review from Code Owners；
- bypass 限制；
- Environment required reviewers；
- prevent self-review；
- Environment deployment branch policy；
- Secrets 的实际权限范围；
- 已部署 Headscale policy 和 preauth key 属性。

## 本次修复

### 1. 无效 CODEOWNERS

原 `CODEOWNERS` 指向 `@bef0rewind`，但审查时该账号对仓库只有 read 权限。GitHub 要求 Code Owner 对仓库具有 write 权限，因此该配置不能构成有效 Code Owner 控制。

已改为当前具有 write 权限的 `@ronhuafeng`，并覆盖 `.github`、scripts、Headscale、tests、docs 和 `SECURITY.md`。

注意：修复文件不等于启用强制审批。管理员仍必须在默认分支 ruleset 中打开 **Require review from Code Owners**，并限制 bypass。

### 2. 带身份信息的本地文件名

原 `.gitignore` 包含一个带个人名称的 secret 文件名。它不直接泄漏 secret 值，但与仓库“公开文件不包含真实成员身份”的隐私目标不一致。

已替换为通用的 `*.secrets.env` 模式。

### 3. 缺少集中安全文档

已增加根目录 `SECURITY.md`，记录 fork 模型、凭证范围、DevSpace 权限、Quick Tunnel 生命周期、Headscale 网络边界、供应链风险和发布检查清单。

`docs/devspace-session.md` 也已补充：

- `enable_devspace=false` 时保持原行为；
- MCP URL 和 Owner Token 的读取方式；
- GitHub 强制销毁 runner 时 Quick Tunnel 的行为；
- fork 和 fork PR 的安全边界。

## 现有有效控制

### GitHub Actions

- workflow 只使用 `workflow_dispatch`；
- workflow 权限限制为 `actions: read` 和 `contents: read`；
- 外部 Actions 固定到完整 commit SHA；
- Environment 名称只能来自公开不透明 allowlist；
- 目标仓库真实名称只来自 Environment Secret；
- 目标 token 使用 path-scoped Git credential helper；
- workflow output 和 artifact 不传递 MCP URL、Owner Token 或诊断文件；
- job 使用 GitHub-hosted 临时 runner，并有六小时平台上限。

### 下载与运行时

- Tailscale 固定版本并验证 SHA-256；
- cloudflared 固定版本并验证 SHA-256；
- DevSpace 固定 npm package version；
- DevSpace 只声明一个允许的 workspace root；
- DevSpace subagents 默认关闭；
- shell command logging 默认关闭；
- cleanup 会尽力终止进程并删除连接文件和 Git credential。

### Headscale policy 示例

- 非空 grants 形成默认拒绝；
- 管理员设备只能访问 runner TCP 22；
- 示例没有赋予 `tag:gha-runner` 主动访问管理员设备的权限；
- Tailscale SSH 仅允许管理员组登录 runner 用户。

## 剩余风险

### 1. GitHub 管理设置未由源码证明

严重性：高（配置依赖）。

源码只能说明应如何配置，不能证明实际 Environment 和默认分支已启用这些保护。尤其需要确认：

```text
main:
  require pull request
  require Code Owner review
  dismiss stale approvals
  require approval of the latest push
  block force push and deletion
  no broad bypass

session--*:
  protected main branch only
  required reviewers
  prevent self-review
  no admin bypass
```

如果 Environment 允许任意 branch，具有 write 权限的人可以在自己的分支修改 workflow，并通过 `workflow_dispatch --ref <branch>` 运行该分支版本。Environment deployment branch policy 是这里的关键控制。

### 2. DevSpace 是 session 内的高权限入口

严重性：高影响、受 OAuth 和临时生命周期限制。

DevSpace 的 workspace allowlist 约束文件工具，但 shell 命令不是操作系统沙箱。已授权 MCP client 可以使用 runner 用户权限；GitHub-hosted runner 通常还允许无密码 `sudo`。当前 session 的目标 Git token、日志和其他本地文件都应被视为该权限边界内可访问。

临时 runner 解决的是持久化问题，不是 session 内权限问题。Owner Token 泄漏或错误批准 MCP client 时，应立即取消 workflow，并撤销目标仓库 token（若怀疑已被读取）。

### 3. npm 供应链

严重性：中。

DevSpace 固定到了明确版本，但全局 npm 安装仍会解析和安装依赖，并可能执行安装脚本。它不像 Tailscale 和 cloudflared 那样由本仓库直接验证单个下载文件的 SHA-256。

升级 DevSpace 时应检查：

- 上游 source diff；
- npm 发布者和版本；
- package lock 变化；
- install/postinstall scripts；
- 新增原生依赖和网络行为；
- 在不含真实凭证的测试 Environment 中进行首次运行。

### 4. Reusable Headscale preauth key

严重性：高影响、由 Environment 保护限制。

如果 reusable key 泄漏，攻击者可能注册额外 tagged runner 节点。必须保持有限有效期、独立服务用户、限定 tag，并记录轮换与撤销流程。Headscale policy 不应允许 runner tag 主动访问其他 tailnet 资产。

### 5. Quick Tunnel 是公网入口

严重性：中、临时。

随机 `trycloudflare.com` URL 不是主要认证凭证，DevSpace OAuth 才是授权边界。URL 和 Owner Token 组合泄漏时，第三方可能在 session 存活期间尝试授权或访问 MCP。

Quick Tunnel 不创建持久 named tunnel。runner 或 cloudflared 进程消失后，URL 不再连接本地服务。

### 6. 缺少真实端到端运行证据

严重性：操作风险。

模拟测试覆盖了文件权限、日志不泄漏、错误码和 cleanup，但不能替代一次真实的 GitHub-hosted runner、Headscale、Cloudflare 和 ChatGPT OAuth 连接测试。

首次生产使用后应记录非敏感验证结果：

- workflow step 成功；
- runner 只通过 tailnet SSH 可达；
- `connection.txt` 权限为 `0600`；
- MCP OAuth 完成；
- 未授权请求被拒绝；
- 取消 job 后 MCP URL 失效；
- Headscale ephemeral node 被清理；
- Actions log 和 artifact 中无内部信息。

## Fork 使用规则

第三方 fork 对上游没有直接凭证风险，但 fork owner 对其 fork 中配置的 Secrets 拥有完整 workflow 控制权。

安全使用 fork 的最低要求：

1. 不复制上游生产 Secrets。
2. 使用独立 Headscale 测试用户和 key。
3. 使用只能访问测试仓库的短期 token。
4. 重新配置 fork 自己的 Environments 和分支保护。
5. 先审查 fork 默认分支中的 workflow 和 scripts，再添加任何 Secret。
6. 测试结束后撤销 key/token，并删除测试节点。

## 最终判断

当前源码结构对“公开仓库被 fork”这一场景采用了合理的隔离模型；fork 不会继承上游权限，fork PR 也不会自动进入特权执行路径。

最需要立即确认的不是 fork 设置，而是上游仓库的默认分支 ruleset 和每个 `session--*` Environment 的保护规则。CODEOWNERS 已修正，但只有管理员启用强制 Code Owner 审批并关闭宽泛 bypass 后，它才成为实际安全控制。