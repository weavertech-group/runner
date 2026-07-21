# DevSpace MCP session

Set `target_id`, `enable_ssh=true`, and `enable_devspace=true` when dispatching
**Private Runner Session**. The workflow clones the selected target repository,
installs DevSpace, starts it on `127.0.0.1:7676`, and exposes it through a new
Cloudflare Quick Tunnel.

Read the connection details through the private tailnet:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
cat ~/private-runner-session/devspace/connection.txt
```

The file contains the MCP URL and Owner Token. It is mode `0600`; do not copy
either value into workflow outputs or artifacts. The URL and token are ephemeral
and change for every session.

DevSpace receives only the cloned target workspace as `DEVSPACE_ALLOWED_ROOTS`,
binds to loopback, disables subagents, and runs with the GitHub-hosted runner
user's privileges. Only connect trusted clients.

The workflow is intentionally happy-path. It does not retry tool installation,
wait for service readiness, or translate failures into custom error codes.
