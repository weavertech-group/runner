# DevSpace MCP session

The private runner workflow can optionally start a DevSpace MCP server for the
selected target repository. The service is disabled by default.

See also the repository-wide [security policy and threat model](../SECURITY.md).

## Disabled behavior

When `enable_devspace` is omitted or set to `false`, the workflow keeps its
original behavior:

1. resolve the optional opaque target;
2. join the private Headscale network when SSH is enabled;
3. configure the selected repository credential when a target is selected;
4. wait in the `Execute` step until cancellation or the hosted-job limit; and
5. perform the normal Tailscale and Git credential cleanup.

No Node.js setup, DevSpace installation, target checkout, cloudflared process,
public MCP endpoint, or connection file is created. The extended finalizer
safely ignores absent DevSpace files and processes.

## Start a session

Dispatch **Private Runner Session** with all of these values:

- `target_id`: an opaque target identifier from `.github/target-repositories.txt`
- `enable_ssh`: `true`
- `enable_devspace`: `true`
- `ssh_public_key`: empty for Tailscale SSH, or a supported Ed25519 key for the
  system OpenSSH fallback

The workflow rejects DevSpace requests that do not select a target repository or
do not enable private SSH access.

The runner then:

1. configures the existing path-scoped Git credential for the selected target;
2. installs Node.js `22.19.0` with a commit-pinned GitHub Action;
3. downloads cloudflared `2026.7.2` and verifies its embedded SHA-256 checksum;
4. installs `@waishnav/devspace@1.0.4`;
5. clones the selected repository into a generic directory under `$RUNNER_TEMP`;
6. starts a Cloudflare Quick Tunnel and DevSpace on `127.0.0.1:7676`;
7. verifies both the local OAuth metadata endpoint and the public tunnel; and
8. writes the connection details to the runner user's home directory.

The private repository name, MCP URL, and Owner Token are not printed to the
public Actions log or written to workflow outputs or artifacts.

## Read the connection details

Connect to the ephemeral runner over the private tailnet:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
```

Then read:

```bash
cat ~/private-runner-session/devspace/connection.txt
```

The file contains:

```text
MCP_URL=https://<quick-tunnel-host>/mcp
OWNER_TOKEN=<random-owner-password>
```

The directory has mode `0700` and the connection files have mode `0600`.

In ChatGPT, create or update the custom MCP connection with `MCP_URL`. When the
DevSpace OAuth approval page opens, enter `OWNER_TOKEN`.

Cloudflare Quick Tunnel hostnames are temporary. A new workflow run produces a
new URL and Owner Token, and both stop working when the job ends.

## Quick Tunnel lifecycle

This workflow uses an anonymous Quick Tunnel rather than a named Cloudflare
Tunnel. It does not create a persistent Cloudflare account resource, custom DNS
record, or stable hostname.

During normal cancellation, the finalizer terminates the DevSpace and
cloudflared process groups and removes the connection files. If GitHub destroys
the hosted runner before the finalizer runs, all local processes and files still
disappear with the virtual machine. The previous `trycloudflare.com` hostname
can no longer reach DevSpace.

The old MCP entry may remain saved in ChatGPT, but it will report a connection
failure. Start a new workflow run, read the newly generated `MCP_URL`, and update
the ChatGPT connection.

## Runtime policy

DevSpace is configured with:

```text
DEVSPACE_ALLOWED_ROOTS=<the cloned target repository only>
DEVSPACE_TOOL_MODE=full
DEVSPACE_WIDGETS=changes
DEVSPACE_SUBAGENTS=0
DEVSPACE_LOG_SHELL_COMMANDS=0
```

DevSpace shell commands still run with the GitHub-hosted runner user's
permissions. The filesystem allowlist is not an operating-system shell sandbox.
The selected repository token must remain limited to that one repository and to
the minimum required permissions.

GitHub-hosted runner isolation limits persistence after the job ends, but it does
not prevent an authenticated MCP client from reading session-local files,
invoking `sudo`, using the selected Git credential, or accessing any network
destination allowed by the deployed Headscale policy. Only authorize a trusted
MCP client.

The workflow does not configure a named Cloudflare Tunnel, a custom domain, or
Cloudflare Access. It uses a temporary Quick Tunnel because the session itself
is ephemeral. For a stable hostname, replace the quick-tunnel launch with a
separately reviewed named-tunnel configuration and keep its credentials in the
selected GitHub Environment.

## Forks and pull requests

A fork receives the public source files but does not inherit the upstream
repository's Secrets, Environments, deployment protection rules, branch
protection, Headscale nodes, or private repository access. Running the workflow
inside a fork therefore requires the fork owner to create a separate set of
credentials and GitHub settings.

Never copy the upstream production `HEADSCALE_AUTHKEY`, `TARGET_REPO_AUTH`, or
other deployment credentials into an untrusted fork. A fork owner can modify the
workflow to print or transmit every credential configured in that fork.

This privileged workflow only uses `workflow_dispatch`; it does not run code
from fork pull requests automatically. However, once a workflow or script change
from a fork is merged into the upstream default branch, later manual runs execute
that merged code with the selected Environment. Workflow, script, policy, and
dependency changes therefore require Code Owner review and protected-branch
enforcement.

## Local diagnostics

Detailed output remains on the ephemeral machine under:

```text
$RUNNER_TEMP/private-runner-diagnostics
```

Useful files include:

```text
cloudflared-install.log
cloudflared.log
devspace-setup.log
devspace.log
```

Do not upload these files as workflow artifacts because clone errors, request
metadata, or tool diagnostics may reveal private information.

## Error codes

| Code | Meaning |
| --- | --- |
| `E50` | DevSpace was requested without a target repository or private SSH |
| `E51` | cloudflared download, checksum, startup, or URL discovery failed |
| `E52` | DevSpace installation, startup, or local readiness failed |
| `E53` | The selected target repository could not be cloned |
| `E54` | The public MCP/OAuth endpoint did not become ready |

The finalizer terminates the DevSpace and cloudflared process groups, removes
the local connection files, deletes the path-scoped Git credential, and logs
out of the Headscale network on a best-effort basis.
