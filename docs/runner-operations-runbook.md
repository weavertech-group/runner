# Private runner operations runbook

This runbook covers the repeatable operation of the public GitHub Actions
workflow in this repository. It intentionally contains no real control-plane
hostname, IP address, person name, private repository name, credential, node
identifier, workflow run identifier, or workstation path.

Use private inventory or a password manager for deployment-specific values.
Do not copy those values into this repository, workflow inputs, run names,
step names, Actions summaries, artifacts, issues, or pull requests.

## Operating model

The workflow creates a temporary GitHub-hosted Ubuntu machine, joins it to a
private Headscale network with a tagged reusable ephemeral preauth key, enables
Tailscale SSH, and waits until the job is cancelled or reaches GitHub's hosted
job limit.

The supported access path is:

```text
authorized workstation -> private tailnet -> ephemeral runner
```

There is no public SSH listener. The runner and Quantumult X workstations do
not install Headscale DNS settings into the operating system. Headscale
MagicDNS remains enabled for other clients that choose to use it.

## Privacy boundaries

The following names are public configuration and may appear in this
repository:

- `tag:gha-runner`
- `runner`
- `HEADSCALE_URL`
- `HEADSCALE_AUTHKEY`
- `TARGET_REPO`
- `TARGET_REPO_AUTH`
- opaque target IDs such as `repo-01`
- Environment names such as `session--repo-01`

Treat all corresponding values as private. In particular, keep these out of
the public repository and public Actions logs:

- the real Headscale URL and tailnet DNS suffix;
- preauth keys, GitHub tokens, SSH private keys, and proxy credentials;
- real member identities and private policy membership;
- private target repository names;
- node addresses, status JSON, internal routes, and detailed diagnostics.

Local private copies may use the ignored files described by `.gitignore`.
Keep their mode at `0600` and never force-add them to Git.

## One-time Headscale setup

1. Merge `headscale/config.example.yaml` into the private deployment.
2. Copy `headscale/policy.example.hujson` to a private policy file.
3. Replace example identities and host aliases using private inventory.
4. Apply `disable-ipv4` only to workstations whose IPv4 routing conflicts with
   another tunnel, and to `tag:gha-runner` when those workstations must access
   runners over IPv6.
5. Validate configuration and policy before activating either one.

For the container deployment used by this project, the validation shape is:

```bash
HEADSCALE_ADMIN_HOST="<private-admin-host>"

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale configtest'
ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale policy check \
    --file /etc/headscale/policy.hujson'
```

Do not publish the private policy: group membership, device aliases, addresses,
and internal routes are operational metadata.

### Create the runner preauth key

Check the installed Headscale version before relying on flags:

```bash
headscale preauthkeys create --help
```

Create a dedicated key under a service user with these properties:

- reusable;
- ephemeral;
- preauthorized;
- tagged `tag:gha-runner`;
- finite expiration.

Never use this key on a personal device. Record its expiration in private
inventory and rotate it before expiry.

## One-time GitHub setup

Create one repository-level Actions secret:

| Scope | Secret | Purpose |
| --- | --- | --- |
| Repository | `HEADSCALE_URL` | Headscale HTTPS control URL |

Do not create a repository-level `HEADSCALE_AUTHKEY`.

Create Environment `session--none` for sessions without a target repository.
It contains only:

```text
HEADSCALE_AUTHKEY
```

For each allowed target repository:

1. Allocate a public opaque ID; never derive it from the repository name.
2. Create Environment `session--<opaque-id>`.
3. Restrict the Environment to the protected default branch.
4. Add required reviewers where appropriate and disable admin bypass.
5. Add exactly these Environment secrets:

   ```text
   HEADSCALE_AUTHKEY
   TARGET_REPO
   TARGET_REPO_AUTH
   ```

6. Give `TARGET_REPO_AUTH` access to only the repository in `TARGET_REPO`.
7. Add only the opaque mapping to `.github/target-repositories.txt`.

List secret names without retrieving their values:

```bash
ORCHESTRATOR_REPO="<public-owner>/<public-repository>"
TARGET_ENVIRONMENT="session--repo-01"

gh secret list --repo "$ORCHESTRATOR_REPO"
gh secret list --repo "$ORCHESTRATOR_REPO" --env session--none
gh secret list --repo "$ORCHESTRATOR_REPO" --env "$TARGET_ENVIRONMENT"
```

Expected isolation:

- repository scope contains only `HEADSCALE_URL`;
- `session--none` contains only `HEADSCALE_AUTHKEY`;
- a target Environment contains one Headscale key, one repository identity,
  and one repository credential;
- no job receives credentials for multiple target repositories.

## Workstation configuration

Give each operator a separate Headscale user. Do not share the runner key with
operators.

On a macOS workstation that coexists with Quantumult X, use the open-source
Tailscale daemon, decline Headscale DNS, and decline routes advertised by other
tailnet nodes:

```bash
sudo tailscale set --accept-dns=false --accept-routes=false
```

The daemon normally runs as a root LaunchDaemon; once installed, routine
`tailscale` CLI use does not require sudo.

Do not add any of the following compatibility workarounds:

- a tailnet domain in Quantumult X DNS rules;
- tailnet IPv4 or IPv6 direct-routing rules in Quantumult X;
- a domain-specific file under `/etc/resolver`;
- an ephemeral runner hostname or address in `~/.ssh/config`;
- the runner's MagicDNS suffix to public DNS.

It is acceptable to retain the conflicting IPv4 range in Quantumult X's
excluded routes; excluded traffic is handed to the underlay rather than owned
by Quantumult X. The Headscale `disable-ipv4` policy removes that address family
from the affected peers' netmaps, so Tailscale does not compete for it.
Headscale's database may still display allocated IPv4 and IPv6 addresses;
validate the client netmap with `tailscale status --json` instead.

## Migrate from the App Store client

This migration replaces the macOS Network Extension client with Homebrew
`tailscaled`. It requires administrator authorization for the system
LaunchDaemon and legacy network-service cleanup.

Before starting, create a short-lived, non-reusable personal preauth key. Note
the old node ID privately, but do not delete it until the replacement has been
verified.

1. Stop the App Store Tailscale client and disable launch-at-login.
2. Remove `Tailscale.app` through Finder. Confirm no Tailscale application is
   running before continuing.
3. Install and start the Homebrew daemon:

   ```bash
   brew install tailscale
   sudo brew services start tailscale
   sudo launchctl print system/homebrew.mxcl.tailscale | \
     grep -E 'state =|pid =|path ='
   ```

4. Join Headscale with the replacement device name and the short-lived
   personal key. Read the key without putting it in shell history:

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

5. Verify `tailscale status`, `tailscale debug prefs`, ordinary internet
   access, Quantumult X, and access to an authorized tailnet peer.
6. Confirm the replacement node owner on Headscale. Only then delete the old
   node and the used personal key.

Remove App Store leftovers after the new daemon is healthy:

```bash
# Confirm exactly one stale App Store VPN entry has this bundle ID.
scutil --nc list | grep 'io.tailscale.ipn.macos'
sudo networksetup -removenetworkservice Tailscale

# Remove this directory only when it is empty.
find /etc/resolver -mindepth 1 -maxdepth 1 -print
sudo rmdir /etc/resolver
```

`networksetup` deletes by display name, not bundle ID. Run it only when the
preceding output identifies one stale App Store entry named `Tailscale` and the
Homebrew daemon is already healthy. If the name is duplicated or ambiguous,
remove the old VPN entry manually in System Settings instead.

Move these obsolete App Store sandbox directories to Trash through Finder:

```text
~/Library/Containers/io.tailscale.ipn.macos
~/Library/Containers/io.tailscale.ipn.macos.login-item-helper
```

macOS may require Full Disk Access. Prefer Finder/Trash so the operation is
recoverable; do not weaken system protection or recursively delete a broader
Containers directory.

## Start a session

Use the Actions UI or GitHub CLI. Inputs and run metadata are public, so pass
only an opaque target ID.

Session without repository access:

```bash
ORCHESTRATOR_REPO="<public-owner>/<public-repository>"

gh workflow run private-runner-session.yml \
  --repo "$ORCHESTRATOR_REPO" \
  --ref main \
  -f enable_ssh=true
```

Session with isolated repository access:

```bash
OPAQUE_TARGET_ID="repo-01"

gh workflow run private-runner-session.yml \
  --repo "$ORCHESTRATOR_REPO" \
  --ref main \
  -f target_id="$OPAQUE_TARGET_ID" \
  -f enable_ssh=true
```

Find the new run without putting a private target name in output:

```bash
gh run list \
  --repo "$ORCHESTRATOR_REPO" \
  --workflow private-runner-session.yml \
  --event workflow_dispatch \
  --limit 5
```

The node name is `gha-${RUN_ID}-${RUN_ATTEMPT}`. Run attempt is normally `1`
for a new dispatch.

## Validate a new session

Do not print full Tailscale status JSON or any environment variables in Actions
logs. Perform the following checks from an authorized workstation.

### 1. Check workflow steps

`Resolve target`, `Connect`, and, when selected, `Prepare repository access`
must complete before `Execute` becomes active:

```bash
RUN_ID="<public-run-id>"

gh run view "$RUN_ID" \
  --repo "$ORCHESTRATOR_REPO" \
  --json status,jobs
```

An unsupported opaque ID must fail in the resolver before a credential-bearing
Environment job starts.

### 2. Check peer identity and address family

```bash
RUN_ATTEMPT="1"
NODE_NAME="gha-${RUN_ID}-${RUN_ATTEMPT}"

tailscale status --json | jq --arg node "$NODE_NAME" '
  [.Peer[] | select(.HostName == $node)][0]
  | {HostName, TailscaleIPs, Online, Relay}'
```

Expected result:

- `Online` is true;
- the affected workstation sees only the runner's tailnet IPv6 address;

The workstation command cannot prove the node's tag or which preauth key
registered it. Verify those separately on the private management host, and do
not paste the resulting metadata into public logs:

```bash
HEADSCALE_ADMIN_HOST="<private-admin-host>"
# Obtain this ID from the private record for the key currently deployed to the
# GitHub Environments; Headscale's node list does not link a node to a key ID.
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

The node must have `tag:gha-runner`. Independently, the key ID recorded for the
current GitHub Environment deployment must be reusable, ephemeral, unexpired,
and restricted to the runner tag. These checks do not prove a node-to-key
causal link; they verify the two independently observable configuration
boundaries. The filter deliberately omits the key value.

A DERP path is valid. GitHub-hosted runners frequently cannot establish a
peer-to-peer path through both endpoints' NAT or VPN configuration. Record the
relay region and latency privately if performance matters; do not treat the
absence of a direct path as an SSH failure.

### 3. Check Tailscale SSH repeatedly

```bash
for check in 1 2 3; do
  tailscale ssh "runner@$NODE_NAME" 'printf ok'
  test "$check" -eq 3 || sleep 15
done
```

All checks must succeed without enabling system MagicDNS, adding an SSH config
alias, supplying a password, or passing an SSH public key.

### 4. Check repository credential isolation

The `Prepare repository access` step confirms that both target secrets exist
and configures a path-scoped Git credential store. For a full private check,
run `git ls-remote` from the SSH session against the internally known target.
Do not put the real repository name in Actions logs:

```bash
tailscale ssh "runner@$NODE_NAME"
# On the runner, using the repository name from private inventory:
GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code \
  "https://github.com/<private-owner>/<private-repository>.git" HEAD \
  >/dev/null
```

The credential helper uses `useHttpPath=true`; a different repository path
must not receive the selected token.

## Keep or end a session

The workflow deliberately waits in `Execute`. It remains online until it is
cancelled or approaches GitHub's six-hour hosted-job limit. Setup time counts
toward that limit.

Cancel deliberately when the session is no longer needed:

```bash
gh run cancel "$RUN_ID" --repo "$ORCHESTRATOR_REPO"
gh run watch "$RUN_ID" --repo "$ORCHESTRATOR_REPO"
```

Expected shutdown behavior:

1. the SSH session terminates;
2. `Finalize` attempts `tailscale logout`;
3. the GitHub-hosted machine and local credential file are destroyed;
4. the old peer disappears from workstation status;
5. Headscale removes the disconnected ephemeral node, immediately or after its
   normal inactivity cleanup.

If cancellation prevents `Finalize`, do not reuse or rename the old node.
Unique run-derived hostnames prevent collisions while ephemeral cleanup catches
up.

## Rotate credentials

### Headscale runner key

1. Create a new tagged reusable ephemeral key with finite expiration.
2. Replace `HEADSCALE_AUTHKEY` in every session Environment.
3. Start a new no-target session and validate SSH.
4. Start one target session and validate repository access.
5. Expire or delete the old key only after both tests pass.

List only non-secret metadata during review. If the CLI JSON includes the key
itself, filter the output before displaying it.

### Target repository token

1. Create a replacement token limited to one repository.
2. Replace `TARGET_REPO_AUTH` only in the matching Environment.
3. Start that opaque target and validate `git ls-remote` over private SSH.
4. Revoke the previous token.

Never combine multiple target tokens into one JSON secret.

### Incident response

If any secret appears in terminal capture, Actions output, an artifact, issue,
pull request, or chat transcript, treat it as exposed even if the repository is
private or the output was later deleted:

1. revoke or expire the credential;
2. create and install a replacement;
3. verify the old credential no longer works;
4. inspect recent workflow runs and Headscale nodes for unexpected use;
5. record the incident without copying the secret value.

## Personal-node migration

Create one Headscale user per person. Migrate a device with a short-lived,
non-reusable personal preauth key. Verify the new owner and connectivity before
deleting the old node.

Migrate ordinary clients before subnet routers. A re-registered subnet router
may need its advertised routes approved again. Do not delete an offline node
whose owner or function has not been confirmed; defer it until the device owner
is available.

Delete used one-time keys after migration. Preserve unused keys only when their
owner, purpose, and expiration remain valid.

## Clean Headscale operational state

Perform cleanup only after the active configuration and current access path
have passed validation. Never delete an offline node solely because it is
offline.

### Inventory before deletion

List nodes and preauth-key metadata on the private management host. Filter out
the preauth key value before displaying or saving output:

```bash
ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale nodes list -o json' | \
  jq 'map({id, name, user: (.user.name // .user), online, tags})'

ssh "$HEADSCALE_ADMIN_HOST" \
  'docker exec headscale headscale preauthkeys list -o json' | \
  jq 'map({id, user: (.user.name // .user), reusable, ephemeral,
           used, expiration, acl_tags})'
```

For every candidate node, confirm its owner, device, route-advertisement role,
replacement node, and last-seen time. Defer uncertain nodes until their owner
is available. Migrate and reapprove subnet routes before removing a router.

### Remove a confirmed stale node or key

Confirm the installed CLI flags first:

```bash
docker exec headscale headscale nodes delete --help
docker exec headscale headscale preauthkeys expire --help
docker exec headscale headscale preauthkeys delete --help
```

For Headscale versions supporting these flags, set the privately reviewed ID
and perform one exact deletion at a time:

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

Expiring first is useful when immediate revocation should precede deletion.
Never delete the currently deployed reusable runner key until every Environment
has been updated and replacement sessions have passed validation.

### Remove temporary policy files

1. Run `configtest` and `policy check` against the active policy.
2. Confirm the active policy is the file referenced by the Headscale config.
3. Compare each candidate or migration backup with the active file and verify
   it is not mounted, referenced, or the only rollback copy.
4. Delete each reviewed obsolete file by its exact path. Do not use a wildcard.
5. Repeat `configtest`, policy validation, node connectivity, and runner SSH.

Keep one intentional, access-controlled rollback source when the active policy
is not versioned elsewhere. Do not accumulate timestamped migration files in
the live configuration directory.

## Troubleshooting

### The hostname does not resolve

This is expected when the workstation declines Tailscale DNS. Use:

```bash
tailscale ssh "runner@$NODE_NAME"
```

Do not enable system MagicDNS merely to make `/usr/bin/ssh` resolve the runner.

### `/usr/bin/ssh` selects a stale address or bind address

Inspect effective configuration:

```bash
/usr/bin/ssh -G "runner@$NODE_NAME" | \
  grep -E '^(hostname|user|addressfamily|bindaddress|proxycommand) '
```

Remove stale runner mappings, `BindAddress`, and old `HostKeyAlias` entries.
Use Tailscale SSH for the default mode.

### Tailscale starts but Quantumult X stops working

Confirm:

```bash
tailscale debug prefs | jq \
  '{ControlURL, RouteAll, CorpDNS, WantRunning}'
```

`RouteAll` and `CorpDNS` should be false on the coexistence workstation. Also
confirm the private policy applies `disable-ipv4` to that exact device and the
runner tag. Remove tailnet-specific Quantumult X DNS and direct-route rules.

### SSH works only through DERP

DERP is a supported encrypted data path. Check repeated SSH success and latency
before changing routing. Do not open public TCP 22 or add a public runner IP.

### Workflow error codes

Use the error-code table in `README.md`. Public logs should contain only the
stable code. Detailed diagnostics stay on the ephemeral runner under
`$RUNNER_TEMP` and must not be uploaded.

## Post-change acceptance checklist

After changing workflow code, Headscale policy, client routing, or credentials:

- [ ] Headscale `configtest` passes.
- [ ] Headscale policy validation passes.
- [ ] The public workflow contains no private deployment values.
- [ ] Repository and Environment secret names match the isolation model.
- [ ] A new node has the unique run-derived name and runner tag.
- [ ] The affected workstation sees the runner over tailnet IPv6 only.
- [ ] Three spaced Tailscale SSH checks pass.
- [ ] The selected target is accessible without printing its token.
- [ ] A different target path cannot obtain that credential.
- [ ] Cancelling the run executes best-effort finalization.
- [ ] The old peer disappears and no stale SSH/DNS workaround remains.
- [ ] Used one-time keys and obsolete temporary policy files are removed.
- [ ] No secret or private identifier appears in the change or logs.

Run the repository checks before committing workflow or documentation changes:

```bash
bash tests/session-lib.test.sh
bash tests/workflow-security.test.sh
git diff --check
```

When recording a validation result, store only the date, pass/fail outcome,
public workflow URL if appropriate, generic failure code, and follow-up owner.
Keep node addresses, real target names, member identities, and diagnostic output
in private operational records.
