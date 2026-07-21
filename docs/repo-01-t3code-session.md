# Repo 01 T3 Code session

Use the **Repo 01 T3 Code Session** workflow when the required operation is fixed:

```text
target_id=repo-01
enable_ssh=true
enable_devspace=false
enable_t3code=true
```

The preset has no operator inputs. It dispatches the existing **Private Runner Session** workflow on `main` using the repository's ephemeral `GITHUB_TOKEN`. The preset does not read or forward Headscale, repository, Lark, T3, or DevSpace credentials.

The downstream session performs the normal implementation:

1. resolve `repo-01` to its protected GitHub Environment;
2. start private SSH through Headscale/Tailscale;
3. install and verify the development environment;
4. clone the target repository into the shared private workspace;
5. start T3 Code and its temporary Cloudflare Quick Tunnel;
6. verify public HTTP and WebSocket readiness;
7. send the T3 URL and, when `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=true`, the temporary Pairing URL to the configured private Lark Webhook group;
8. keep the session alive until cancellation or the six-hour hosted-runner limit.

The generic **Private Runner Session** workflow remains available for SSH-only, DevSpace, combined-service, alternate-target, and fallback public-key sessions.

## Failure interpretation

The preset dispatch job only confirms that GitHub accepted the downstream workflow dispatch. The actual runner status and T3 access information are reported by the downstream workflow and Lark notifications.

A successful T3 notification contains:

```text
T3 Code online
Target: repo-01
T3 URL: https://<temporary>.trycloudflare.com
Pairing URL: https://<temporary>.trycloudflare.com/pair#token=<temporary-token>
```

The Pairing URL is included only when the repository variable `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS` is exactly `true`.
