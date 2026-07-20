# DevSpace MCP session

The private runner workflow can optionally start a DevSpace MCP server for the
selected target repository. The service is disabled by default.

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
permissions. The selected repository token must remain limited to that one
repository and to the minimum required permissions.

The workflow does not configure a named Cloudflare Tunnel, a custom domain, or
Cloudflare Access. It uses a temporary Quick Tunnel because the session itself
is ephemeral. For a stable hostname, replace the quick-tunnel launch with a
separately reviewed named-tunnel configuration and keep its credentials in the
selected GitHub Environment.

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
