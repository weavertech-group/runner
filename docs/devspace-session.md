# DevSpace MCP session

The private runner workflow can optionally start a DevSpace MCP server for the
selected target repository. The service is disabled by default and is exposed
through a pre-created Cloudflare Named Tunnel with a stable HTTPS hostname.

See also the repository-wide [security policy and threat model](../SECURITY.md)
and the [T3 Code session guide](t3code-session.md).

## Required configuration

For each opaque target, configure a remotely-managed Cloudflare Tunnel and a
DevSpace hostname that routes to:

```text
https://mcp-repo-07.example.com -> http://127.0.0.1:7676
```

Store these values in the target's `session--<opaque-id>` GitHub Environment:

```text
CLOUDFLARE_TUNNEL_TOKEN=<target-specific tunnel token>
DEVSPACE_PUBLIC_URL=https://mcp-repo-07.example.com
```

When T3 Code is also enabled, use a separate hostname for T3. The two services
must not share one hostname or use path prefixes.

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
4. installs pinned `@waishnav/devspace@1.0.4`;
5. starts DevSpace on `127.0.0.1:7676` using the fixed public base URL;
6. starts the pre-created Named Tunnel using a mode-`0600` token file;
7. verifies the local OAuth metadata and public protected-resource endpoints; and
8. writes the connection details to the runner user's home directory.

T3 Code, DevSpace, SSH users, Codex, and Claude share the same Git working tree
when those services are enabled together.

## Read the connection details

Connect over the private tailnet:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
cat ~/private-runner-session/devspace/connection.txt
```

The file contains:

```text
MCP_URL=https://mcp-repo-07.example.com/mcp
OWNER_TOKEN=<random-owner-password>
```

The directory has mode `0700` and the connection files have mode `0600`. The MCP
URL and Owner Token are not written to workflow outputs, artifacts, or public
Actions logs.

The public hostname remains stable across workflow runs. The Owner Token changes
on every run and stops working when the ephemeral runner is destroyed.

## Named Tunnel lifecycle

The workflow does not create Cloudflare account resources. An administrator
pre-creates the Tunnel, DNS record, and published application route. The
workflow only starts a connector using `CLOUDFLARE_TUNNEL_TOKEN`.

Sessions for the same opaque target are serialized. Running the same Tunnel token
from two different opaque targets would still create Cloudflare replicas and can
route requests to inconsistent runner state, so do not reuse a Tunnel credential
between targets.

During normal finalization, the workflow terminates DevSpace and cloudflared,
removes the Tunnel token file and connection files, deletes the shared workspace,
and removes the repository credential. The stable hostname remains configured
but has no healthy origin after the job ends.

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
Headscale access, private repository credentials, Cloudflare Tunnel tokens, or
stable hostnames. Never copy production credentials into an untrusted fork.

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
cloudflared.log
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
| `E51` | cloudflared installation, token/configuration, or connector startup failed |
| `E52` | DevSpace installation, startup, or local readiness failed |
| `E53` | The selected target repository could not be cloned |
| `E54` | The public MCP/OAuth endpoint did not become ready |
