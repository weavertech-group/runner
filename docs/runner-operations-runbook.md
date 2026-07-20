# 私有 Runner 运维手册

本手册说明如何重复执行本公开 GitHub Actions workflow 的运维操作。本文刻意
不包含真实的控制平面域名、IP 地址、成员姓名、私有仓库名、凭证、节点标识、
workflow run ID 或工作站本机路径。

部署相关的真实值应保存在私有资产清单或密码管理器中。不要将这些值复制到本
仓库、workflow inputs、run 名称、step 名称、Actions summary、artifact、
issue 或 pull request 中。

## 运行模型

Workflow 会创建一台临时 GitHub-hosted Ubuntu 机器，使用带 tag、可复用且
ephemeral 的 preauth key 加入私有 Headscale 网络，启用 Tailscale SSH，然后
等待 job 被取消或达到 GitHub-hosted job 时长限制。

支持的访问路径为：

```text
已授权工作站 -> 私有 tailnet -> 临时 runner
```

Runner 不开放公网 SSH。Runner 和与 Quantumult X 共存的工作站不把 Headscale
DNS 设置写入操作系统。Headscale MagicDNS 继续为选择使用它的其他客户端启用。

## 隐私边界

以下名称属于公开配置，可以出现在本仓库中：

- `tag:gha-runner`
- `runner`
- `HEADSCALE_URL`
- `HEADSCALE_AUTHKEY`
- `TARGET_REPO`
- `TARGET_REPO_AUTH`
- `repo-01` 之类的不透明 target ID
- `session--repo-01` 之类的 Environment 名称

对应的值均应视为私密信息。尤其不要让以下内容出现在公开仓库或公开 Actions
日志中：

- 真实 Headscale URL 和 tailnet DNS 后缀；
- preauth key、GitHub token、SSH 私钥和代理凭证；
- 真实成员身份和私有 policy 成员关系；
- 私有目标仓库名称；
- 节点地址、完整 status JSON、内部路由和详细诊断信息。

本地私有副本可以使用 `.gitignore` 中声明的忽略文件。其权限应保持为 `0600`，
且绝不能使用 Git 强制添加。

## 一次性 Headscale 配置

1. 将 `headscale/config.example.yaml` 合并到私有部署配置中。
2. 将 `headscale/policy.example.hujson` 复制为私有 policy 文件。
3. 根据私有资产清单替换示例身份和 host alias。
4. 只对 IPv4 路由与另一个隧道冲突的工作站应用 `disable-ipv4`；当这些工作站
   需要访问 runner 时，也对 `tag:gha-runner` 应用该属性。
5. 启用配置和 policy 前分别执行校验。

对于本项目使用的容器部署，校验命令形式如下：

```bash
HEADSCALE_ADMIN_HOST="<private-admin-host>"

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale configtest'
ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale policy check \
    --file /etc/headscale/policy.hujson'
```

不要公开私有 policy。组成员、设备 alias、地址和内部路由都属于运维元数据。

### 创建 Runner preauth key

使用相关参数前先检查已安装 Headscale 版本：

```bash
headscale preauthkeys create --help
```

在专用服务用户下创建具有以下属性的 key：

- reusable；
- ephemeral；
- preauthorized；
- 带有 `tag:gha-runner`；
- 有限有效期。

绝不能在个人设备上使用该 key。将其过期时间记录在私有资产清单中，并在到期
前轮换。

## 一次性 GitHub 配置

创建一个 repository-level Actions secret：

| Scope | Secret | 用途 |
| --- | --- | --- |
| Repository | `HEADSCALE_URL` | Headscale HTTPS 控制端点 |

不要创建 repository-level `HEADSCALE_AUTHKEY`。

为不访问目标仓库的 session 创建 Environment `session--none`，其中只能包含：

```text
HEADSCALE_AUTHKEY
```

针对每个允许的目标仓库：

1. 分配一个公开的不透明 ID，且绝不能从仓库名派生。
2. 创建 Environment `session--<opaque-id>`。
3. 将该 Environment 限制为受保护的默认分支。
4. 根据需要添加 required reviewers，并关闭 admin bypass。
5. 添加且仅添加以下 Environment secrets：

   ```text
   HEADSCALE_AUTHKEY
   TARGET_REPO
   TARGET_REPO_AUTH
   ```

6. `TARGET_REPO_AUTH` 只能访问 `TARGET_REPO` 指定的单一仓库。
7. 只把不透明映射加入 `.github/target-repositories.txt`。

以下命令只列出 secret 名称，不读取其值：

```bash
ORCHESTRATOR_REPO="<public-owner>/<public-repository>"
TARGET_ENVIRONMENT="session--repo-01"

gh secret list --repo "$ORCHESTRATOR_REPO"
gh secret list --repo "$ORCHESTRATOR_REPO" --env session--none
gh secret list --repo "$ORCHESTRATOR_REPO" --env "$TARGET_ENVIRONMENT"
```

预期隔离结果：

- repository scope 只能包含 `HEADSCALE_URL`；
- `session--none` 只能包含 `HEADSCALE_AUTHKEY`；
- target Environment 包含一个 Headscale key、一个仓库身份和一个仓库凭证；
- 任何 job 都不能同时获得多个目标仓库的凭证。

## 工作站配置

为每位操作者创建独立 Headscale 用户。不要与操作者共享 runner key。

对于与 Quantumult X 共存的 macOS 工作站，使用开源 Tailscale daemon，拒绝
Headscale DNS，并拒绝其他 tailnet 节点发布的路由：

```bash
sudo tailscale set --accept-dns=false --accept-routes=false
```

Daemon 通常以 root LaunchDaemon 运行。安装完成后，日常使用 `tailscale` CLI
不需要 sudo。

不要添加以下任何兼容性 workaround：

- 在 Quantumult X DNS 规则中添加 tailnet 域名；
- 在 Quantumult X 中添加 tailnet IPv4 或 IPv6 直连规则；
- 在 `/etc/resolver` 下添加特定域名文件；
- 在 `~/.ssh/config` 中固定临时 runner 的 hostname 或地址；
- 将 runner 的 MagicDNS 后缀加入公共 DNS。

Quantumult X 的 excluded routes 中可以继续保留发生冲突的 IPv4 网段；被排除
的流量会交给 underlay，而不是由 Quantumult X 自身接管。Headscale 的
`disable-ipv4` policy 会从相关 peer 的 netmap 中移除该地址族，因此 Tailscale
不会与其竞争。Headscale 数据库仍可能显示已分配的 IPv4 和 IPv6 地址；应使用
`tailscale status --json` 验证客户端实际收到的 netmap。

## 从 App Store 客户端迁移

该流程使用 Homebrew `tailscaled` 替换 macOS Network Extension 客户端。系统
LaunchDaemon 和旧网络服务清理需要管理员授权。

开始前，创建一个短期、不可复用的个人 preauth key。私下记录旧节点 ID，但在
验证替代节点前不要删除旧节点。

1. 停止 App Store Tailscale 客户端，并关闭登录时启动。
2. 通过 Finder 删除 `Tailscale.app`。继续前确认没有 Tailscale 应用进程运行。
3. 安装并启动 Homebrew daemon：

   ```bash
   brew install tailscale
   sudo brew services start tailscale
   sudo launchctl print system/homebrew.mxcl.tailscale | \
     grep -E 'state =|pid =|path ='
   ```

4. 使用替代设备名和短期个人 key 加入 Headscale。通过静默输入避免 key 进入
   shell history：

   ```bash
   HEADSCALE_URL="<private-control-url>"
   DEVICE_NAME="<private-device-name>"
   read -rsp 'Personal preauth key: ' PERSONAL_AUTHKEY
   printf '\n'

   sudo tailscale up \
     --login-server="$HEADSCALE_URL" \
     --auth-key="$PERSONAL_AUTHKEY" \
     --hostname="$DEVICE_NAME" \
     --accept-dns=false \
     --accept-routes=false
   unset PERSONAL_AUTHKEY
   ```

5. 验证 `tailscale status`、`tailscale debug prefs`、普通互联网访问、
   Quantumult X，以及对一个已授权 tailnet peer 的访问。
6. 在 Headscale 上确认替代节点的 owner。只有完成确认后，才能删除旧节点和
   已使用的个人 key。

新 daemon 健康后再删除 App Store 残留：

```bash
# 确认只有一个旧 App Store VPN 条目使用该 bundle ID。
scutil --nc list | grep 'io.tailscale.ipn.macos'
sudo networksetup -removenetworkservice Tailscale

# 仅当此目录为空时删除。
find /etc/resolver -mindepth 1 -maxdepth 1 -print
sudo rmdir /etc/resolver
```

`networksetup` 根据显示名称而不是 bundle ID 删除服务。只有当前一条命令确认
存在唯一、名为 `Tailscale` 的旧 App Store 条目，且 Homebrew daemon 已健康
时，才能运行删除命令。如果名称重复或目标有歧义，应在 System Settings 中
手工删除旧 VPN 条目。

通过 Finder 将以下过时 App Store sandbox 目录移入废纸篓：

```text
~/Library/Containers/io.tailscale.ipn.macos
~/Library/Containers/io.tailscale.ipn.macos.login-item-helper
```

macOS 可能要求 Full Disk Access。优先使用 Finder/废纸篓以便恢复；不要降低
系统保护，也不要递归删除更上层的 Containers 目录。

## 启动 Session

可以使用 Actions UI 或 GitHub CLI。Inputs 和 run metadata 都是公开信息，
因此只能传入不透明 target ID。

启动不包含仓库访问权限的 session：

```bash
ORCHESTRATOR_REPO="<public-owner>/<public-repository>"

gh workflow run private-runner-session.yml \
  --repo "$ORCHESTRATOR_REPO" \
  --ref main \
  -f enable_ssh=true
```

启动带隔离仓库访问权限的 session：

```bash
OPAQUE_TARGET_ID="repo-01"

gh workflow run private-runner-session.yml \
  --repo "$ORCHESTRATOR_REPO" \
  --ref main \
  -f target_id="$OPAQUE_TARGET_ID" \
  -f enable_ssh=true
```

查找新 run 时不要输出私有 target 名称：

```bash
gh run list \
  --repo "$ORCHESTRATOR_REPO" \
  --workflow private-runner-session.yml \
  --event workflow_dispatch \
  --limit 5
```

节点名称是 `gha-${RUN_ID}-${RUN_ATTEMPT}`。新 dispatch 的 run attempt 通常为
`1`。

## 验证新 Session

不要在 Actions 日志中输出完整 Tailscale status JSON 或任何环境变量。以下
检查应从已授权工作站执行。

### 1. 检查 Workflow steps

`Resolve target`、`Connect`，以及选择 target 时的
`Prepare repository access` 必须先完成，随后 `Execute` 才会进入 active：

```bash
RUN_ID="<public-run-id>"

gh run view "$RUN_ID" \
  --repo "$ORCHESTRATOR_REPO" \
  --json status,jobs
```

不支持的不透明 ID 必须在 resolver 中失败，并且失败发生在带凭证的
Environment job 启动之前。

### 2. 检查 Peer 身份和地址族

```bash
RUN_ATTEMPT="1"
NODE_NAME="gha-${RUN_ID}-${RUN_ATTEMPT}"

tailscale status --json | jq --arg node "$NODE_NAME" '
  [.Peer[] | select(.HostName == $node)][0]
  | {HostName, TailscaleIPs, Online, Relay}'
```

预期结果：

- `Online` 为 true；
- 相关工作站只看到 runner 的 tailnet IPv6 地址。

工作站上的命令无法证明节点 tag，也无法证明由哪个 preauth key 注册。应在私有
管理主机上分别验证这些信息，并且不要把输出元数据粘贴到公开日志：

```bash
HEADSCALE_ADMIN_HOST="<private-admin-host>"
# 从 GitHub Environments 当前部署 key 的私有记录中取得该 ID；
# Headscale 节点列表不会把节点关联到 key ID。
RUNNER_KEY_ID="<private-key-id>"

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale nodes list -o json' | \
  jq --arg node "$NODE_NAME" '
    [.[] | select(.name == $node)][0]
    | {id, name, online, tags}'

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale preauthkeys list -o json' | \
  jq --argjson id "$RUNNER_KEY_ID" '
    [.[] | select(.id == $id)][0]
    | {id, reusable, ephemeral, expiration, acl_tags}'
```

节点必须带有 `tag:gha-runner`。独立地，私有部署记录中对应当前 GitHub
Environment 的 key 必须是 reusable、ephemeral、尚未过期，并且只允许 runner
tag。这些检查不能证明 node-to-key 因果关联；它们分别验证两个可以独立观察的
配置边界。过滤器刻意省略 key 值。

DERP 是有效路径。由于两端 NAT 或 VPN 配置，GitHub-hosted runner 经常无法
建立 peer-to-peer 路径。如果性能很重要，可以在私有记录中保存 relay region
和延迟；不能因为没有直连就判定 SSH 失败。

### 3. 重复检查 Tailscale SSH

```bash
for check in 1 2 3; do
  tailscale ssh "runner@$NODE_NAME" 'printf ok'
  test "$check" -eq 3 || sleep 15
done
```

所有检查都必须成功，且不需要启用系统 MagicDNS、不需要 SSH config alias、
不需要密码，也不需要传 SSH public key。

### 4. 检查仓库凭证隔离

`Prepare repository access` step 会确认两个 target secrets 均存在，并配置
path-scoped Git credential store。要进行完整私有验证，应从 SSH session 内对
私有资产清单中的目标运行 `git ls-remote`。不要将真实仓库名写入 Actions
日志：

```bash
tailscale ssh "runner@$NODE_NAME"
# 在 runner 上使用私有资产清单中的仓库名称：
GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code \
  "https://github.com/<private-owner>/<private-repository>.git" HEAD \
  >/dev/null
```

Credential helper 使用 `useHttpPath=true`；不同仓库路径不能获得当前选择的
token。

## 保持或结束 Session

Workflow 会刻意停留在 `Execute`。它会持续在线，直到被取消或接近 GitHub
六小时 hosted-job 限制。Setup 时间也计入该限制。

Session 不再需要时应主动取消：

```bash
gh run cancel "$RUN_ID" --repo "$ORCHESTRATOR_REPO"
gh run watch "$RUN_ID" --repo "$ORCHESTRATOR_REPO"
```

预期关闭行为：

1. SSH session 终止；
2. `Finalize` 尝试执行 `tailscale logout`；
3. GitHub-hosted 机器及其本地 credential 文件被销毁；
4. 旧 peer 从工作站 status 中消失；
5. Headscale 立即或通过正常 inactivity cleanup 删除断开的 ephemeral 节点。

如果取消导致 `Finalize` 没有执行，不要复用或重命名旧节点。基于 run 的唯一
hostname 可以在等待 ephemeral cleanup 时避免名称冲突。

## 轮换凭证

### Headscale Runner key

1. 创建一个新的、带 tag、reusable、ephemeral 且具有有限有效期的 key。
2. 替换所有 session Environment 中的 `HEADSCALE_AUTHKEY`。
3. 启动新的 no-target session 并验证 SSH。
4. 启动一个 target session 并验证仓库访问。
5. 两项测试都通过后，才能 expire 或删除旧 key。

审查时只列出非敏感元数据。如果 CLI JSON 包含 key 本身，显示输出前必须过滤。

### 目标仓库 token

1. 创建一个只能访问单一仓库的替代 token。
2. 只替换对应 Environment 中的 `TARGET_REPO_AUTH`。
3. 启动对应不透明 target，并通过私有 SSH 验证 `git ls-remote`。
4. 撤销旧 token。

绝不能把多个 target token 合并到一个 JSON secret 中。

### 事件响应

如果任何 secret 出现在终端录屏、Actions 输出、artifact、issue、pull request
或聊天记录中，即使仓库是 private 或输出后来被删除，也应视为已泄露：

1. revoke 或 expire 该凭证；
2. 创建并安装替代凭证；
3. 确认旧凭证不再有效；
4. 检查近期 workflow runs 和 Headscale nodes 是否存在异常使用；
5. 记录事件，但不要复制 secret 值。

## 个人节点迁移

每个人创建独立 Headscale 用户。使用短期、不可复用的个人 preauth key 迁移
设备。删除旧节点前必须验证新 owner 和网络连通性。

先迁移普通客户端，最后迁移 subnet router。重新注册 subnet router 后，可能
需要重新批准其 advertised routes。不要因为节点离线就删除 owner 或用途尚未
确认的节点；应等设备 owner 可以配合时再处理。

迁移后删除已使用的一次性 key。只有 owner、用途和 expiration 仍然有效时，
才保留尚未使用的 key。

## 清理 Headscale 运维状态

只有在 active 配置和当前访问路径都通过验证后才能清理。绝不能仅因为节点
离线就删除它。

### 删除前盘点

在私有管理主机上列出 nodes 和 preauth key 元数据。显示或保存输出前必须过滤
preauth key 值：

```bash
ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale nodes list -o json' | \
  jq 'map({id, name, user: (.user.name // .user), online, tags})'

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale preauthkeys list -o json' | \
  jq 'map({id, user: (.user.name // .user), reusable, ephemeral,
           used, expiration, acl_tags})'
```

对每个候选节点确认其 owner、设备、route advertisement 职责、替代节点和
last-seen 时间。无法确认的节点应延后，直到 owner 可以配合。删除 router 前
必须迁移并重新批准 subnet routes。

### 删除已确认的旧节点或 key

先确认当前安装版本的 CLI 参数：

```bash
docker exec headscale headscale nodes delete --help
docker exec headscale headscale preauthkeys expire --help
docker exec headscale headscale preauthkeys delete --help
```

对于支持以下参数的 Headscale 版本，设置已私下复核的 ID，每次只执行一个精确
删除操作：

```bash
STALE_NODE_ID="<confirmed-node-id>"
USED_KEY_ID="<confirmed-key-id>"

docker exec headscale headscale nodes delete \
  --force --identifier "$STALE_NODE_ID"
docker exec headscale headscale preauthkeys expire \
  --force --id "$USED_KEY_ID"
docker exec headscale headscale preauthkeys delete \
  --force --id "$USED_KEY_ID"
```

需要立即撤销时，可以先 expire 再 delete。在所有 Environment 完成更新且替代
session 通过验证前，绝不能删除当前部署的 reusable runner key。

### 删除临时 Policy 文件

1. 对 active policy 执行 `configtest` 和 `policy check`。
2. 确认 active policy 就是 Headscale config 引用的文件。
3. 将每个 candidate 或迁移备份与 active 文件比较，并确认它没有被 mount、
   reference，也不是唯一 rollback 副本。
4. 使用精确路径逐个删除已确认无用的文件，不要使用 wildcard。
5. 再次执行 `configtest`、policy validation、节点连通性和 runner SSH。

如果 active policy 没有在其他位置进行版本管理，应保留一个有访问控制且用途
明确的 rollback 来源。不要在 live 配置目录中积累带时间戳的迁移文件。

## 故障排查

### Hostname 无法解析

工作站拒绝 Tailscale DNS 时，这是预期行为。使用：

```bash
tailscale ssh "runner@$NODE_NAME"
```

不要仅为了让 `/usr/bin/ssh` 解析 runner 就启用系统 MagicDNS。

### `/usr/bin/ssh` 选择了旧地址或 bind address

检查有效配置：

```bash
/usr/bin/ssh -G "runner@$NODE_NAME" | \
  grep -E '^(hostname|user|addressfamily|bindaddress|proxycommand) '
```

删除旧 runner mapping、`BindAddress` 和过时的 `HostKeyAlias`。默认模式应使用
Tailscale SSH。

### Tailscale 启动后 Quantumult X 无法工作

确认：

```bash
tailscale debug prefs | jq \
  '{ControlURL, RouteAll, CorpDNS, WantRunning}'
```

在共存工作站上，`RouteAll` 和 `CorpDNS` 应为 false。同时确认私有 policy 对
该准确设备和 runner tag 应用了 `disable-ipv4`。删除 Quantumult X 中 tailnet
专用的 DNS 和直连路由规则。

### SSH 只能通过 DERP 工作

DERP 是受支持的加密数据路径。修改路由前先检查重复 SSH 是否成功以及延迟。
不要开放公网 TCP 22，也不要给 runner 添加公网 IP。

### Workflow 错误码

使用 `README.md` 中的错误码表。公开日志只能包含稳定错误码。详细诊断保留在
临时 runner 的 `$RUNNER_TEMP` 下，不得上传。

## 变更后验收清单

修改 workflow 代码、Headscale policy、客户端路由或凭证后：

- [ ] Headscale `configtest` 通过。
- [ ] Headscale policy validation 通过。
- [ ] 公开 workflow 不包含私有部署值。
- [ ] Repository 和 Environment secret 名称符合隔离模型。
- [ ] 新节点具有基于 run 的唯一名称和 runner tag。
- [ ] 相关工作站只能通过 tailnet IPv6 看到 runner。
- [ ] 三次间隔执行的 Tailscale SSH 检查都通过。
- [ ] 可以访问选中的 target，且没有输出 token。
- [ ] 不同 target path 无法获得该 credential。
- [ ] 取消 run 时执行了 best-effort finalization。
- [ ] 旧 peer 消失，并且没有残留 SSH/DNS workaround。
- [ ] 已使用的一次性 key 和过时临时 policy 文件已删除。
- [ ] 变更和日志中不存在 secret 或私有标识。

提交 workflow 或文档变更前运行仓库检查：

```bash
bash tests/session-lib.test.sh
bash tests/workflow-security.test.sh
git diff --check
```

记录验证结果时，只保存日期、pass/fail 结果、适当情况下可公开的 workflow
URL、通用 failure code 和 follow-up owner。节点地址、真实 target 名称、成员
身份和诊断输出应保存在私有运维记录中。
