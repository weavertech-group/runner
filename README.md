# Private GitHub Actions runner session

This public repository starts an ephemeral GitHub-hosted Ubuntu runner, joins it
to a private Headscale network, and keeps it available over Tailscale SSH. The
runner has no public SSH listener. An optional `owner/repository` input selects
exactly one GitHub Environment and therefore exactly one repository credential.

The workflow is intentionally only a secure network/SSH handoff. It does not
run issue agents, create pull requests, or implement a task queue.

## What is implemented

- Unique node name: `gha-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}`.
- Pinned Tailscale `1.94.2` Linux binary with an embedded SHA-256 check.
- Headscale URL override, MagicDNS validation, and Tailscale SSH by default.
- Optional Ed25519 public-key mode using system OpenSSH on the tailnet only.
- Explicit target allowlist and one GitHub Environment per target repository.
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

### 2. Configure repository settings

Create these repository-level Actions settings:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `HEADSCALE_AUTHKEY` | The tagged ephemeral preauth key |
| Variable | `HEADSCALE_URL` | `https://headscale.example.com` |
| Variable | `HEADSCALE_MAGIC_DNS_DOMAIN` | `mesh.example.net` |

Create a credential-free GitHub Environment named `repo--none`. The workflow
uses it when no target repository is selected, so no repository token is
referenced or installed.

For each allowed repository:

1. Create an environment such as `repo--alice--private-api`.
2. Add environment secret `TARGET_REPO_AUTH`, using a fine-grained PAT limited
   to that one repository. A short-lived GitHub App token issuer is preferred
   for a later production phase.
3. Add the exact mapping to [.github/target-repositories.txt](.github/target-repositories.txt):

   ```text
   alice/private-api repo--alice--private-api
   ```

The mapping is explicit rather than computed so different repository names can
never collide onto the same environment. The resolver rejects all targets not
in this file before the credential-bearing job starts.

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
optional `target_repo` value must match the allowlist. Leave `ssh_public_key`
empty for the default Tailscale SSH mode.

The host is:

```text
gha-<run-id>-<run-attempt>.<magic-dns-domain>
```

Connect from an authorized workstation:

```bash
ssh runner@gha-<run-id>-<run-attempt>.mesh.example.net
```

When a target was selected, Git is configured to return the environment token
only for that repository path, so this works without putting a token in the
command line:

```bash
git clone https://github.com/alice/private-api.git
```

Supplying `ssh_public_key` switches the session to system OpenSSH. Only
`ssh-ed25519` and `sk-ssh-ed25519@openssh.com` single-line keys are accepted;
password, keyboard-interactive, and root login remain disabled. Tailscale SSH
is not enabled in this fallback mode because it owns tailnet TCP port 22 and
would bypass `authorized_keys`.

The session step sleeps for four hours. The job timeout is 330 minutes. Ending
or cancelling the workflow destroys the GitHub-hosted runner and its Git
credential file; the cleanup step also attempts an immediate Headscale logout.

## Error codes

Only stable error codes are printed publicly:

| Code | Meaning | Where detected |
| --- | --- | --- |
| `E10` | unsupported or malformed `target_repo` | resolver |
| `E11` | selected GitHub Environment unavailable | GitHub API preflight |
| `E12` | `TARGET_REPO_AUTH` missing or not installed | runner |
| `E20` | Tailscale download, checksum, or install failure | runner |
| `E21` | daemon startup or Headscale connection failure | runner |
| `E22` | missing, invalid, or expired Headscale key | runner |
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
