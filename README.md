# Private GitHub Actions runner session

This public repository starts an ephemeral GitHub-hosted Ubuntu runner, joins it
to a private Headscale network, and keeps it available over Tailscale SSH. The
runner has no public SSH listener. An optional opaque target ID selects exactly
one GitHub Environment without exposing the private repository name.

By default, the workflow is only a secure network/SSH handoff. An explicit
`enable_devspace` option can additionally clone the selected target repository,
start a DevSpace MCP server, and expose it through a temporary Cloudflare Quick
Tunnel. It does not run issue agents, create pull requests, or implement a task
queue.

For repeatable setup, operation, validation, credential rotation, cleanup, and
troubleshooting, use the privacy-safe
[operations runbook](docs/runner-operations-runbook.md). The optional MCP service
is documented separately in the [DevSpace session guide](docs/devspace-session.md).
This README describes the design invariants.

## What is implemented

- Unique node name: `gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}`.
- Pinned Tailscale `1.94.2` Linux binary with an embedded SHA-256 check.
- Headscale URL override and Tailscale SSH without changing runner DNS.
- Optional Ed25519 public-key mode using system OpenSSH on the tailnet only.
- Public opaque-ID allowlist and one GitHub Environment per target repository.
- A path-scoped Git credential store for the selected repository only.
- Optional DevSpace `1.0.4` with Node.js `22.19.0`.
- Pinned cloudflared `2026.7.2` Linux binary with an embedded SHA-256 check.
- DevSpace MCP URL and Owner Token stored only in a mode-`0600` local file.
- Minimal public output; detailed local diagnostics are never uploaded.
- Best-effort service termination, logout, and ephemeral-node cleanup when a job
  is cancelled.

## Required administrator setup

### 1. Configure Headscale

Merge [the config example](headscale/config.example.yaml) into the deployed
Headscale configuration. The public control URL and MagicDNS base domain must
be different DNS names. Validate and restart using commands appropriate to the
installed Headscale version, for example:

```bash
headscale configtest
sudo systemctl restart headscale
```

Deploy a private copy of [the policy example](headscale/policy.example.hujson).
Replace the example identity with the real team group. Do not publish the real
policy here because member identities can be sensitive.

Adding a non-empty `grants` array changes the tailnet from Headscale's implicit
allow-all behavior to explicit authorization. Before enabling it, inventory
existing personal-node traffic and subnet routes and add grants for the traffic
that must remain available. The example preserves full connectivity between
members of `group:platform-admins`; add explicit CIDR destinations for any
existing subnet routes.

The policy example also enables the `magicdns-aaaa` node attribute. Keep this
for clients that choose to use MagicDNS when the Headscale IPv6 pool is
enabled. Runner sessions and workstations that coexist with Quantumult X do
not install these DNS settings into the operating system.

The example additionally uses `hosts` aliases to apply the official
`disable-ipv4` node attribute only to the macOS devices that coexist with
Quantumult X and to `tag:gha-runner`. Replace the example host addresses with
those devices' current Headscale IPv4 addresses before deploying the policy.
This makes their Tailnet path IPv6-only: Quantumult X keeps ownership of IPv4
and system DNS, while Tailscale avoids the conflicting `100.64.0.0/10` range.

Create a dedicated tagged, reusable, ephemeral, pre-authorized key. Confirm the
flags against the installed version:

```bash
headscale preauthkeys create --help
headscale preauthkeys create \
  --user gha \
  --reusable \
  --ephemeral \
  --tags tag:gha-runner \
  --expiration 720h
```

Team workstations must join the same Headscale network and be included in
`group:platform-admins` (or the replacement group). A workstation that
coexists with Quantumult X must join with `--accept-dns=false` so Quantumult X
remains the only manager of system DNS.

Give each person a separate Headscale user. On Headscale versions without a
node-owner transfer command, an existing device must reauthenticate under its
new user. Migrate ordinary clients first and subnet routers last, because a
re-registered subnet router may need its advertised routes approved again. Use
a short-lived, non-reusable key for one device at a time:

```bash
headscale users create MEMBER
headscale preauthkeys create --user MEMBER_ID --expiration 24h
```

After the member reconnects, verify the node owner, MagicDNS name, peer access,
and any routes before deleting or expiring the old node record.

### 2. Configure repository settings

Create this repository-level Actions secret. The URL is sensitive metadata
rather than an authentication credential, but storing it as a secret gives it
the same automatic log masking as other Actions secrets.

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `HEADSCALE_URL` | The externally reachable HTTPS control URL |

Do not create repository-level `HEADSCALE_AUTHKEY`, because any other trusted
workflow in the repository could reference it. Create a GitHub Environment
named `session--none` containing only environment secret `HEADSCALE_AUTHKEY`.
The workflow uses this Environment when no target is selected.

For each allowed repository:

1. Allocate a public opaque ID such as `repo-07`.
2. Create an Environment such as `session--repo-07`.
3. Add these Environment secrets:

   | Secret | Value |
   | --- | --- |
   | `HEADSCALE_AUTHKEY` | The tagged ephemeral preauth key |
   | `TARGET_REPO` | The real private `owner/repository` name |
   | `TARGET_REPO_AUTH` | A token limited to that repository |

4. Add only the opaque mapping to [.github/target-repositories.txt](.github/target-repositories.txt):

   ```text
   repo-07 session--repo-07
   ```

Never put a real private repository name in the public allowlist, Environment
name, workflow input, run name, or step name. The resolver rejects opaque IDs
not in the allowlist before the credential-bearing job starts.

For every session Environment, restrict deployment branches to the protected
default branch, enable required reviewers where appropriate, and disable admin
bypass. The workflow also sets `deployment: false`, so using Environment
secrets does not create a public deployment record.

### 3. Protect the public repository

The included [CODEOWNERS](.github/CODEOWNERS) assigns the current maintainer to
workflow, network, and allowlist changes. Replace or extend `@bef0rewind` with
the actual security review team. Then configure a default-branch ruleset that:

- requires a pull request and CODEOWNER approval;
- blocks force pushes and branch deletion;
- restricts who can push;
- requires approval for changes under `.github/workflows/**` if supported by
  the organization's ruleset setup.

Do not add `pull_request_target`, do not run fork-provided code in this workflow,
and keep every external Action pinned to a full commit SHA. Workflow dispatch
inputs and run metadata in this public repository must be treated as public.

## Start and connect

From the Actions UI, choose **Private Runner Session** and dispatch it. The
optional `target_id` value must match the opaque allowlist. Leave `ssh_public_key`
empty for the default Tailscale SSH mode.

The node name is:

```text
gha-<run-id>-<run-attempt>
```

On macOS workstations that run Quantumult X, use the Homebrew/open-source
`tailscaled` client and prevent it from changing system DNS:

```bash
sudo tailscale set --accept-dns=false
```

Connect through the Tailscale CLI. It resolves the node from the local daemon
even when system DNS integration is disabled. The `disable-ipv4` policy makes
the selected workstation and runner use their conflict-free Tailnet IPv6
addresses automatically:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
```

Do not enable **Use Tailscale DNS settings**, add a Quantumult X DNS override,
create `/etc/resolver` entries, or pin ephemeral runner addresses in
`~/.ssh/config`. Headscale MagicDNS remains enabled for other clients that want
it; these workstations and the GitHub-hosted runner simply decline its system
DNS configuration.

When a target was selected, Git is configured from the protected `TARGET_REPO`
secret and returns the token only for that repository path. An authorized
operator can clone the internally known repository without putting a token in
the command line:

```bash
git clone https://github.com/<owner>/<repository>.git
```

To start DevSpace automatically, select a non-empty `target_id`, keep
`enable_ssh` enabled, and set `enable_devspace` to `true`. After connecting over
private SSH, read the MCP URL and Owner Token:

```bash
cat ~/private-runner-session/devspace/connection.txt
```

Use the `MCP_URL` value when configuring ChatGPT. Enter `OWNER_TOKEN` when the
DevSpace OAuth approval page opens. The quick-tunnel URL and token expire with
the runner session. See the [DevSpace session guide](docs/devspace-session.md)
for the full procedure and runtime policy.

Supplying `ssh_public_key` switches the session to system OpenSSH. Only
`ssh-ed25519` and `sk-ssh-ed25519@openssh.com` single-line keys are accepted;
password, keyboard-interactive, and root login remain disabled. Tailscale SSH
is not enabled in this fallback mode because it owns tailnet TCP port 22 and
would bypass `authorized_keys`. Find the current runner IPv6 address with
`tailscale status`, then connect to that address with `ssh -6`.

The session step waits indefinitely and the job timeout is 360 minutes, so the
runner stays online until GitHub enforces its six-hour hosted-job limit. Setup
time is part of that limit, so usable SSH time is slightly less than six full
hours. Ending or cancelling the workflow destroys the GitHub-hosted runner and
its local connection files; when GitHub gives finalization steps time to run,
the cleanup step also stops DevSpace and cloudflared, removes Git credentials,
and attempts an immediate Headscale logout. Otherwise Headscale's ephemeral-node
inactivity cleanup removes the disconnected node.

## Error codes

Only stable error codes are printed publicly:

| Code | Meaning | Where detected |
| --- | --- | --- |
| `E10` | unsupported or malformed opaque `target_id` | resolver |
| `E11` | selected GitHub Environment unavailable | GitHub API preflight |
| `E12` | selected `TARGET_REPO` or credential missing/invalid | runner |
| `E20` | Tailscale download, checksum, or install failure | runner |
| `E21` | invalid HTTPS URL, unhealthy control plane, or daemon startup failure | runner |
| `E22` | registration rejected after a successful Headscale health check | runner |
| `E24` | selected SSH server cannot be enabled | runner |
| `E25` | Headscale grant or SSH policy denies the member | SSH client/policy logs |
| `E30` | fallback SSH public key is invalid | runner |
| `E40` | job reaches its configured timeout | GitHub Actions conclusion |
| `E41` | run is cancelled | GitHub Actions conclusion |
| `E50` | DevSpace requested without a target repository or private SSH | runner |
| `E51` | cloudflared download, checksum, startup, or URL discovery failure | runner |
| `E52` | DevSpace installation, startup, or local readiness failure | runner |
| `E53` | selected target repository clone failure | runner |
| `E54` | public DevSpace MCP/OAuth endpoint readiness failure | runner |

`E25`, `E40`, and `E41` are platform/client outcomes and cannot reliably be
emitted by a runner step: a denied client never executes code on the runner,
and timeout/cancellation can terminate the machine before another step runs.

Detailed command output stays under `$RUNNER_TEMP/private-runner-diagnostics`
on the ephemeral machine. It is not printed, summarized, or uploaded. DevSpace
connection material is stored separately under
`~/private-runner-session/devspace` and is deleted during finalization.

## Local validation

```bash
bash tests/session-lib.test.sh
bash tests/workflow-security.test.sh
bash tests/devspace-session.test.sh
bash -n scripts/*.sh tests/*.sh
```
