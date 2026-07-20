# Private GitHub Actions runner session

This public repository starts an ephemeral GitHub-hosted Ubuntu runner, joins it
to a private Headscale network, and keeps it available over Tailscale SSH. The
runner has no public SSH listener. An optional opaque target ID selects exactly
one GitHub Environment without exposing the private repository name.

The workflow is intentionally only a secure network/SSH handoff. It does not
run issue agents, create pull requests, or implement a task queue.

## What is implemented

- Unique node name: `gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}`.
- Pinned Tailscale `1.94.2` Linux binary with an embedded SHA-256 check.
- Headscale URL override, MagicDNS validation, and Tailscale SSH by default.
- Optional Ed25519 public-key mode using system OpenSSH on the tailnet only.
- Public opaque-ID allowlist and one GitHub Environment per target repository.
- A path-scoped Git credential store for the selected repository only.
- Minimal public output; detailed local diagnostics are never uploaded.
- Best-effort logout plus ephemeral-node cleanup when a job is cancelled.

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
when the Headscale IPv6 pool is enabled: it lets MagicDNS clients use the
tailnet IPv6 address if a local network incorrectly claims the CGNAT
`100.64.0.0/10` range.

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

Team workstations must join the same Headscale network, accept its DNS settings,
and be included in `group:platform-admins` (or the replacement group).

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

Create these repository-level Actions secrets. The URL and DNS suffix are
sensitive metadata rather than authentication credentials, but storing them as
secrets gives them the same automatic log masking as other Actions secrets.

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `HEADSCALE_URL` | The externally reachable HTTPS control URL |
| Secret | `HEADSCALE_MAGIC_DNS_DOMAIN` | The private MagicDNS suffix |

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

The host is:

```text
gha-<run-id>-<run-attempt>.<magic-dns-domain>
```

Connect from an authorized workstation:

```bash
ssh runner@gha-<run-id>-<run-attempt>.mesh.example.net
```

When a target was selected, Git is configured from the protected `TARGET_REPO`
secret and returns the token only for that repository path. An authorized
operator can clone the internally known repository without putting a token in
the command line:

```bash
git clone https://github.com/<owner>/<repository>.git
```

Supplying `ssh_public_key` switches the session to system OpenSSH. Only
`ssh-ed25519` and `sk-ssh-ed25519@openssh.com` single-line keys are accepted;
password, keyboard-interactive, and root login remain disabled. Tailscale SSH
is not enabled in this fallback mode because it owns tailnet TCP port 22 and
would bypass `authorized_keys`.

The session step waits indefinitely and the job timeout is 360 minutes, so the
runner stays online until GitHub enforces its six-hour hosted-job limit. Setup
time is part of that limit, so usable SSH time is slightly less than six full
hours. Ending or cancelling the workflow destroys the GitHub-hosted runner and
its Git credential file; when GitHub gives finalization steps time to run, the
cleanup step also attempts an immediate Headscale logout. Otherwise Headscale's
ephemeral-node inactivity cleanup removes the disconnected node.

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
| `E23` | MagicDNS name missing or has the wrong suffix | runner |
| `E24` | selected SSH server cannot be enabled | runner |
| `E25` | Headscale grant or SSH policy denies the member | SSH client/policy logs |
| `E30` | fallback SSH public key is invalid | runner |
| `E40` | job reaches its configured timeout | GitHub Actions conclusion |
| `E41` | run is cancelled | GitHub Actions conclusion |

`E25`, `E40`, and `E41` are platform/client outcomes and cannot reliably be
emitted by a runner step: a denied client never executes code on the runner,
and timeout/cancellation can terminate the machine before another step runs.

Detailed command output stays under `$RUNNER_TEMP/private-runner-diagnostics`
on the ephemeral machine. It is not printed, summarized, or uploaded.

## Local validation

```bash
bash tests/session-lib.test.sh
bash tests/workflow-security.test.sh
bash -n scripts/*.sh tests/*.sh
```
