# T3 Code session

Set `target_id`, `enable_ssh=true`, and `enable_t3code=true` when dispatching
**Private Runner Session**. The workflow clones the selected target repository,
starts `npx t3@latest` on `127.0.0.1:3773`, and creates a Cloudflare Quick
Tunnel.

Read the pairing URL through the private tailnet:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
cat ~/private-runner-session/t3code/connection.txt
```

The public URL, pairing URL, cloned working tree, and T3's own state are
ephemeral. T3 and DevSpace share the cloned working tree when both are enabled,
but each uses its own Quick Tunnel URL. The pairing URL is copied directly from
T3's output; the workflow does not construct or rewrite it.

The workflow is intentionally happy-path. It does not retry installation or
perform local/public readiness checks; failed commands retain their native
output and exit status in the Actions log.
