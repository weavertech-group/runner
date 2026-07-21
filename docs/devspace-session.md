# DevSpace MCP session

The private runner workflow can optionally start a DevSpace MCP server for the
selected target repository. The service is disabled by default and is exposed
through a temporary Cloudflare Quick Tunnel with a random HTTPS URL.

See also the repository-wide [security policy and threat model](../SECURITY.md)
and the [T3 Code session guide](t3code-session.md).

## Required configuration

No Cloudflare account setup is required. The workflow creates an anonymous Quick
Tunnel to `http://127.0.0.1:7676` during each enabled session.

The target's GitHub Environment only needs the normal Headscale and repository
secrets documented in the README. Do not add Cloudflare account credentials or a
preconfigured DevSpace URL.

## Start a session

Dispatch **Private Runner Session** with:

- `target_id`: an opaque target identifier from `.github/target-repositories.txt`;
- `enable_ssh`: `true`;
- `enable_devspace`: `true`;
- `ssh_public_key`: empty for Tailscale SSH, or a supported Ed25519 key for the
  system OpenSSH fallback.

The workflow rejects optional public service requests that do not select a
target repository or do not enable private SSH access.

The runner then:

1. configures the path-scoped Git credential for the selected target;
2. clones the selected repository once into `$RUNNER_TEMP/target-workspace`;
3. downloads the pinned `cloudflared` binary and verifies its checksum;
4. starts a dedicated Quick Tunnel and records its random URL privately;
5. installs pinned `@waishnav/devspace@1.0.4`;
6. starts DevSpace on `127.0.0.1:7676` using that URL as its public base URL;
7. verifies the local OAuth metadata and public protected-resource endpoints; and
8. writes the connection details to the runner user's home directory.

T3 Code, DevSpace, SSH users, Codex, and Claude share the same Git working tree
when those services are enabled together. T3 Code receives a different Quick
Tunnel URL.

## Read the connection details

Connect over the private tailnet:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
cat ~/private-runner-session/devspace/connection.txt
```

The file contains values similar to:

```text
MCP_URL=https://random-name.trycloudflare.com/mcp
OWNER_TOKEN=<random-owner-password>
```

The directory has mode `0700` and the connection files have mode `0600`. The MCP
URL and Owner Token are not written to workflow outputs, artifacts, or public
Actions logs.

## Quick Tunnel lifecycle

A new workflow run creates a new URL and Owner Token. Both stop working when the
runner session ends. Update any saved MCP connection with the current URL.

The workflow creates no Cloudflare account resource, DNS record, custom hostname,
or long-lived connector credential. During normal finalization it terminates
DevSpace and its Quick Tunnel process, removes connection and URL files, deletes
the shared workspace, and removes the repository credential.

Concurrent sessions for the same opaque target are allowed because every run has
an independent workspace, DevSpace state directory, Quick Tunnel, and Owner Token.

## Runtime policy

DevSpace is configured with:

```text
DEVSPACE_ALLOWED_ROOTS=<the shared target workspace only>
DEVSPACE_TOOL_MODE=full
DEVSPACE_WIDGETS=changes
DEVSPACE_SUBAGENTS=0
DEVSPACE_LOG_SHELL_COMMANDS=0
```

DevSpace shell commands still run with the GitHub-hosted runner user's
permissions. The filesystem allowlist is not an operating-system shell sandbox.
An authenticated MCP client can execute commands, use the selected Git
credential, invoke `sudo`, and reach network destinations allowed by the runner's
network policy. Only authorize a trusted MCP client.

## Forks and pull requests

Forks do not inherit upstream Secrets, Environments, deployment protection,
Headscale access, or private repository credentials. Never copy production
credentials into an untrusted fork.

This privileged workflow remains manual-only. Workflow, script, dependency, and
security-policy changes require protected-branch and Code Owner review because a
later trusted dispatch executes the merged code with Environment secrets.

## Local diagnostics

Detailed output remains under:

```text
$RUNNER_TEMP/private-runner-diagnostics
```

Useful files include:

```text
cloudflared-install.log
cloudflared-devspace.log
devspace-setup.log
devspace.log
public-services.log
workspace-setup.log
```

Do not upload these files as artifacts.

## Error codes

| Code | Meaning |
| --- | --- |
| `E50` | An optional public service was requested without a target or private SSH |
| `E51` | cloudflared installation, Quick Tunnel startup, or URL discovery failed |
| `E52` | DevSpace installation, startup, or local readiness failed |
| `E53` | The selected target repository could not be cloned |
| `E54` | The public MCP/OAuth endpoint did not become ready |
