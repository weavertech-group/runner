# T3 Code session

The private runner workflow can optionally start T3 Code for the selected target
repository and expose it through a temporary Cloudflare Quick Tunnel. The runner,
T3 state, public URL, and pairing credential are all ephemeral.

See also the repository-wide [security policy and threat model](../SECURITY.md).

## Required configuration

No Cloudflare account setup is required. The workflow downloads the pinned
`cloudflared` binary and creates an anonymous Quick Tunnel to
`http://127.0.0.1:3773` during each run.

The target's GitHub Environment only needs the normal Headscale and repository
secrets documented in the README. Do not add Cloudflare account credentials or a
preconfigured public URL for T3 Code.

## Start a session

Dispatch **Private Runner Session** with:

- a non-empty allowed `target_id`;
- `enable_ssh=true`;
- `enable_t3code=true`;
- optionally `enable_devspace=true`.

The workflow then:

1. configures the target-scoped Git credential;
2. clones the selected repository once into a shared temporary workspace;
3. installs pinned `t3@0.0.28`;
4. starts a dedicated Quick Tunnel and records its random HTTPS URL privately;
5. adds the workspace as a T3 project;
6. starts T3 Code on `127.0.0.1:3773`;
7. verifies public HTTPS access and the T3 WebSocket upgrade; and
8. stores the current URL and pairing information in private local files.

T3 Code and DevSpace operate on the same Git working tree when both are enabled,
but each service receives a separate Quick Tunnel URL.

## Read the pairing URL

Connect over the private tailnet and read:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
cat ~/private-runner-session/t3code/connection.txt
```

The file contains values similar to:

```text
T3_URL=https://random-name.trycloudflare.com
PAIRING_URL=https://random-name.trycloudflare.com/pair#token=<one-time-credential>
```

Neither the URL nor the pairing credential is printed to the public Actions log.
Open `PAIRING_URL` in a browser or use it to add the environment in a T3 Code
client.

## Lifecycle and persistence

The following are intentionally ephemeral:

- the cloned working tree;
- T3 project and thread state;
- T3 pairing and session credentials;
- the Quick Tunnel URL and process;
- DevSpace state and Owner Token when DevSpace is enabled.

The public URL changes on every run and stops working when the runner session
ends. Commit and push any required repository changes before the GitHub-hosted
job ends. Do not place the T3 data directory, provider credential directories,
private source tree, or connection files in an Actions cache or artifact.

Concurrent sessions for the same opaque target are allowed because each run has
its own workspace, T3 state, Quick Tunnel process, and random URL.

## Provider availability

The workflow installs current Codex CLI and Claude Code releases before starting
T3 Code. Installation does not by itself authenticate either provider. Provider
credentials must be supplied through a separately reviewed, non-interactive,
target-scoped mechanism before the corresponding provider can be used.

The first implementation does not install Grok, Cursor Agent, or OpenCode.

## Failure codes

| Code | Meaning |
| --- | --- |
| `E50` | An optional public service was requested without a target or private SSH |
| `E51` | cloudflared installation, Quick Tunnel startup, or URL discovery failed |
| `E53` | The selected target repository could not be cloned |
| `E61` | The pinned T3 Code package could not be installed or verified |
| `E62` | T3 project initialization, startup, or local readiness failed |
| `E63` | Public T3 HTTPS or WebSocket readiness failed |

Detailed output remains under `$RUNNER_TEMP/private-runner-diagnostics` and is
not uploaded.
