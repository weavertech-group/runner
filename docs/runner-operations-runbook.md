# Private runner operations

## Start a session

Dispatch **Private Runner Session** from the Actions UI. Leave `target_id` empty
for an SSH-only session, or select an opaque ID from
`.github/target-repositories.txt`. The selected ID maps to the GitHub
Environment that provides the private Headscale and target-repository secrets.

Set `enable_ssh=true` for private access. Use the default Tailscale SSH mode or
provide an `ssh_public_key` for system OpenSSH restricted to the runner's
tailnet IPv6 address.

Set `enable_devspace=true` or `enable_t3code=true` only with a selected target
and private SSH. The workflow clones the target and writes the generated
connection information under `~/private-runner-session`.

## Connect

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
```

For the OpenSSH fallback, find the runner's tailnet IPv6 address with
`tailscale status` and connect with `ssh -6`.

Read optional-service connection details over that private SSH connection:

```bash
cat ~/private-runner-session/devspace/connection.txt
cat ~/private-runner-session/t3code/connection.txt
```

## Failure behavior

This repository deliberately models the happy path. A workflow command prints
its native output and fails with its native exit status. There are no repository
specific error codes, retries, readiness probes, or diagnostic artifacts.

## Local checks

```bash
bash tests/happy-path-workflow.test.sh
bash tests/lark-webhook.test.sh
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
```
