# 安全策略与威胁模型

本仓库公开 workflow 和脚本，但真实基础设施、私有仓库身份和所有凭证必须始终保存在仓库外。公开源码本身不是秘密；安全性依赖最小权限凭证、GitHub Environment 保护规则、受保护默认分支，以及 Headscale policy 的共同约束。

## 安全边界

本项目创建临时 GitHub-hosted Ubuntu runner，并可选择启用：

- 通过 Headscale/Tailscale 提供的私有 SSH；
- 对一个选定目标仓库的路径限定 Git 凭证；
- DevSpace MCP 和临时 Cloudflare Quick Tunnel。

GitHub-hosted runner 会在 job 结束后销毁。临时机器降低持久化风险，但不是进程级或命令级沙箱。任何获得 DevSpace MCP 命令执行权限、SSH 权限，或能修改并运行受信任 workflow 的主体，都应视为在当前 session 内获得了 runner 用户权限。

## Fork 安全模型

别人 fork 本仓库不会自动获得上游仓库的以下内容：

- repository、organization 或 Environment Secrets；
- GitHub Environments 及其审批规则；
- 分支保护、rulesets 和 Actions 管理设置；
- Headscale 节点、preauth key 或真实 target 映射；
- 目标私有仓库权限。

Fork 中的 workflow 只能使用 fork 自己配置的凭证。来自 fork 的 pull request 也不会因为本仓库的源码而自动获得上游 Secrets。本项目的特权 workflow 只使用 `workflow_dispatch`，不会自动执行 fork PR 中的代码。

这并不意味着 fork 可以被盲目信任：

1. Fork owner 可以任意修改 workflow 和脚本。
2. 如果有人把上游使用的真实 `HEADSCALE_AUTHKEY`、`TARGET_REPO_AUTH` 或其他凭证复制到 fork，修改后的 fork workflow 可以读取或外传这些凭证。
3. Fork 不继承上游 Environment 的 required reviewers、deployment branch policy 或 branch protection。
4. Fork 中的公开 allowlist、变量名和示例配置不构成授权；真实权限完全取决于 fork owner 自己配置的 Secrets 和基础设施。

因此绝不能把上游生产凭证复制到第三方 fork。需要测试 fork 时，应创建独立 Headscale 用户和 tag、独立短期 preauth key、独立测试仓库 token，并在测试结束后撤销。

## 上游 pull request 风险

Fork PR 本身不能读取上游 Secrets，但一旦恶意或未经充分审查的 workflow、shell 脚本、Headscale policy 或依赖版本变更被合并，后续人工 dispatch 会在受信任 Environment 中运行合并后的代码。

以下路径必须视为安全敏感：

```text
.github/
scripts/
headscale/
tests/workflow-security.test.sh
SECURITY.md
```

必须在默认分支 ruleset 中启用：

- 所有变更必须通过 pull request；
- Require review from Code Owners；
- 至少一名非提交者批准；
- 新提交后撤销过期批准；
- 禁止 force push 和分支删除；
- 禁止或严格限制 bypass；
- 对 workflow 文件要求额外审批（组织设置支持时）。

`CODEOWNERS` 只有在 owner 具有 write 权限，并且 ruleset/branch protection 要求 Code Owner 审批时才构成强制控制。文件本身不会自动阻止合并。

## GitHub Environment 必需配置

每个 `session--*` Environment 必须：

- 只允许受保护的默认分支部署；
- 配置 required reviewers；
- 启用 prevent self-review；
- 禁止管理员随意 bypass；
- 只保存该 Environment 所需的 Secrets。

推荐范围：

```text
Repository secret:
  HEADSCALE_URL

session--none:
  HEADSCALE_AUTHKEY

session--<opaque-id>:
  HEADSCALE_AUTHKEY
  TARGET_REPO
  TARGET_REPO_AUTH
```

`TARGET_REPO_AUTH` 必须限定到单个仓库和最少权限。不要使用组织管理员 token、classic PAT 的宽泛 `repo` 权限，或能读取其他仓库 Secrets/Actions 设置的凭证。

## DevSpace 与 Cloudflare 风险

启用 `enable_devspace` 后：

- DevSpace shell 命令以 GitHub-hosted runner 用户运行；
- GitHub-hosted runner 通常允许该用户使用 `sudo`；
- DevSpace 文件根目录限制不等同于 shell 沙箱；
- 当前目标仓库凭证在 session 内可供 Git 使用；
- Quick Tunnel URL 是公网地址，访问控制依赖 DevSpace OAuth Owner Token；
- npm 包及其依赖会在 runner 上执行安装代码。

因此只应把 MCP 连接授权给可信 ChatGPT 会话。不要把 `connection.txt`、Owner Token、DevSpace 日志或 Cloudflare 日志上传为 artifact 或粘贴到公开 issue/PR。

Quick Tunnel 是临时开发通道。`cloudflared` 进程或 runner 消失后，该随机地址不再连接到本地服务。它不会在 Cloudflare 账户中创建需要长期维护的 named tunnel，但 ChatGPT 中保存的旧 MCP 配置会保持存在并显示连接失败。

## Headscale 网络边界

部署的 policy 应保持默认拒绝，并只允许管理员工作站连接 runner 的 TCP 22。不要授予 `tag:gha-runner` 主动访问管理员设备、私有服务或广泛 subnet routes 的权限。

Reusable runner preauth key 泄漏后可能允许攻击者注册新的 tagged 节点。它必须：

- 存放在 Environment Secret 中，而不是 repository Secret；
- 设置有限有效期；
- 只允许 `tag:gha-runner`；
- 定期轮换；
- 发生疑似泄漏时立即撤销并清理异常节点。

## 供应链控制

当前控制包括：

- 外部 GitHub Actions 固定到完整 commit SHA；
- Tailscale 和 cloudflared 固定版本并校验 SHA-256；
- DevSpace 固定到明确 npm 版本。

剩余风险是 npm 依赖树和安装脚本。更新 DevSpace、Node.js、Tailscale、cloudflared 或任何 Action 时，应单独审查发布来源、变更内容和校验值，并通过测试分支验证后再合并。

## 日志与本地文件

公开 Actions 输出只能包含稳定错误码和非敏感状态。以下内容必须留在临时 runner 本地：

- MCP URL 和 Owner Token；
- Headscale URL、auth key 和内部地址；
- 目标私有仓库名称；
- Git credential 文件；
- 完整 Tailscale status；
- DevSpace、cloudflared 和连接诊断日志。

正常 finalization 会终止相关进程并删除连接材料。GitHub 直接销毁虚拟机时，即使 finalizer 未执行，所有本地文件和进程仍会随机器消失。

## 安全审查清单

发布或配置变更前至少确认：

```text
[ ] workflow 仍只由 workflow_dispatch 触发
[ ] 未加入 pull_request_target、issue_comment 或特权 workflow_run 执行路径
[ ] 所有第三方 Action 固定到完整 SHA
[ ] Environment 只允许受保护默认分支
[ ] Environment required reviewers 和 prevent self-review 已开启
[ ] CODEOWNERS 中的 owner 具有 write 权限
[ ] 默认分支要求 Code Owner 审批且无宽泛 bypass
[ ] target token 只访问一个仓库
[ ] Headscale grants 不允许 runner 主动横向访问
[ ] 日志和 artifact 不包含凭证或内部元数据
[ ] DevSpace/Cloudflare/Tailscale 版本和校验值已经复核
```

## 报告安全问题

不要在公开 issue、pull request 或讨论中提交真实凭证、私有仓库内容、内部地址、完整日志或可利用细节。

优先使用 GitHub Private Vulnerability Reporting（若仓库已启用）。若未启用，应私下联系仓库维护者，并仅提供最小复现信息。发现凭证泄漏时，先撤销和轮换凭证，再进行后续调查。