# Lark reporting

The runner reports lifecycle and optional-service availability to one fixed private Lark group through a signed custom-bot Webhook.

```text
runner lifecycle or service state
  -> normalized session event
  -> scripts/report-session-event.sh
  -> signed Lark custom-bot Webhook
  -> restricted internal group
```

The workflow emits backend-neutral events. It does not contain Webhook request JSON, signing logic, or destination selection. Future `lark-cli` IM and Lark Base consumers can reuse the same non-sensitive event model without replacing the workflow integration.

## Scope

The Webhook MVP reports:

```text
starting
ssh-online
setup-ready or setup-degraded
service-online: devspace
service-online: t3code
offline
```

DevSpace and T3 Code are independent. A run that enables both services receives one service notification for each service that passes public readiness verification.

Reporting is an operational convenience layer. Private SSH and the mode-`0600` connection files remain the fallback and canonical source for local session access.

## Create the Lark custom bot

1. Create or select a private internal operations group.
2. Restrict group membership to people allowed to see runner connection information.
3. Add a custom bot to the group.
4. Use the current V2 Webhook URL.
5. Enable signature verification in the bot security settings.
6. Copy both the Webhook URL and signing secret into GitHub Secrets.

The Webhook URL itself grants message-delivery capability and must be treated as a credential. Do not place it in a Repository Variable, workflow input, repository file, issue, log, artifact, or cache.

Keyword protection may be enabled only when the chosen keyword appears in every fixed message. GitHub-hosted runners do not have one stable outbound address, so IP allowlisting is not the primary control for this integration.

## GitHub configuration

Repository Secrets:

```text
LARK_WEBHOOK_URL
LARK_WEBHOOK_SECRET
```

Repository Variables:

```text
LARK_REPORTING_ENABLED=true
LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=false
```

### `LARK_REPORTING_ENABLED`

Only the exact value `true` enables external reporting. Missing, empty, or any other value makes every reporting command a successful no-op.

Disable reporting immediately by setting this variable to `false` or removing the Webhook Secrets.

### `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS`

This variable defaults to `false`.

When false, service messages contain public service URLs but leave temporary access material available only through private SSH:

```text
DevSpace -> MCP URL only
T3 Code  -> T3 public URL only
```

When exactly `true`, the matching private-group message may additionally contain:

```text
DevSpace -> current session OWNER_TOKEN
T3 Code  -> current session PAIRING_URL
```

The T3 Pairing URL contains its pairing token in the URL fragment and is treated as a credential. Enabling this option means temporary access material remains in Lark group history. Use it only for a tightly restricted operations group.

No workflow input can enable temporary-access delivery or change the destination.

## Event contract

The public reporter interface is:

```bash
bash scripts/report-session-event.sh <event>
```

Accepted events:

```text
starting
ssh-online
setup-ready
setup-degraded
service-online
offline
```

`service-online` additionally requires one allowlisted service identifier:

```bash
SESSION_SERVICE=devspace bash scripts/report-session-event.sh service-online
SESSION_SERVICE=t3code bash scripts/report-session-event.sh service-online
```

Unknown events and service names are rejected before an external request.

Generic event fields are limited to:

```text
event
session_key
target_id
github_run_id
github_run_attempt
actions_url
setup_status
ssh_online
service
service_online
service_url
runner_name
occurred_at
expires_at
error_code
```

The generic event object never contains:

```text
DevSpace OWNER_TOKEN
T3 PAIRING_URL
raw T3 pairing token
Webhook credentials
repository or infrastructure credentials
```

This separation allows a future status or Base backend to consume service state and public URLs without receiving temporary credentials.

## Lifecycle and ordering

The workflow uses this order:

```text
restore caches
  -> starting
  -> prepare and connect private network
  -> ssh-online, after successful connection
  -> install and verify development environment
  -> setup-ready or setup-degraded
  -> start optional service tools, workspace, and Quick Tunnels
  -> start DevSpace and/or T3 Code
  -> verify each enabled public service
  -> one service-online event per verified service
  -> long-running session
  -> offline during normal finalization
  -> cleanup
```

A forced GitHub-hosted runner termination may prevent `offline` from executing. Every earlier message includes one stable absolute expiry calculated from the six-hour job limit; use that timestamp as the stale-session fallback.

## Message contents

Ordinary lifecycle messages may contain:

- opaque target ID;
- GitHub run ID, attempt, and Actions URL;
- safe runner node name;
- setup and SSH state;
- absolute timestamps and expiry;
- a stable non-sensitive error/status code.

Service messages may additionally contain:

- service name;
- DevSpace MCP URL or T3 public URL;
- matching temporary access material only when explicitly enabled.

`offline` never repeats a service URL, Owner Token, Pairing URL, or pairing token.

## Delivery deduplication

Successful delivery creates a private marker under:

```text
~/private-runner-session/lark-events/
```

The directory uses mode `0700`; marker files use mode `0600`. Each marker stores only:

```text
delivered
```

There is one marker per lifecycle event and one marker per service for `service-online`. Markers never store message bodies, URLs, signatures, API responses, or credentials.

Behavior:

- a successfully delivered event is not resent by an ordinary workflow retry;
- a failed delivery is not marked and may be retried;
- DevSpace and T3 Code deduplicate independently;
- once `setup-ready` succeeds, `setup-degraded` is suppressed, and vice versa;
- cleanup removes all marker state.

This is deliberately a local best-effort mechanism, not a durable queue or database.

## Authentication and signing

The backend implements the Lark custom-bot signing contract:

1. obtain the current Unix timestamp in seconds;
2. form `timestamp + "\n" + signing secret`;
3. use that byte string as the HMAC-SHA256 key for an empty message;
4. Base64-encode the digest;
5. send `timestamp`, `sign`, `msg_type`, and `content` in the JSON body.

No Lark App ID, App Secret, OAuth login, access-token storage, or `@larksuite/cli` installation is required for this MVP.

## Failure behavior

All reporting is best effort:

- disabled or unconfigured reporting exits successfully;
- configuration, signing, local file, network, and Lark API failures do not change setup status or job success;
- reporting cannot block SSH, repository access, development setup, DevSpace, T3 Code, the long-running session, or cleanup;
- HTTP retries are bounded and short;
- one service notification failure does not suppress the other service;
- local connection files remain available through SSH after notification failure.

## Private diagnostics

Non-sensitive reporting diagnostics are written to:

```text
$RUNNER_TEMP/private-runner-diagnostics/lark-webhook.log
```

The directory uses mode `0700`; the file uses mode `0600`. Entries contain stable categories and event/service names only.

Diagnostics must not contain:

- Webhook URL or signing secret;
- generated signature;
- full request payload or response;
- Owner Token or Pairing URL;
- repository, Headscale, Cloudflare, GitHub, Codex, or Claude credentials.

The diagnostics directory is not uploaded as a public artifact.

## Security model

Never send through this integration:

```text
LARK_WEBHOOK_URL
LARK_WEBHOOK_SECRET
HEADSCALE_AUTHKEY
TARGET_REPO_AUTH
GitHub PATs
Cloudflare API credentials
reusable preauth keys
Codex or Claude provider credentials
access tokens or refresh tokens
long-lived cross-session credentials
```

Additional invariants:

- no shell tracing, broad environment dump, or credential output;
- no Webhook credentials, signatures, or temporary access material in `GITHUB_OUTPUT`, step summaries, artifacts, caches, setup status, setup details, or diagnostics;
- connection and delivery-state files remain private and are removed by cleanup;
- the privileged runner workflow remains `workflow_dispatch` only;
- pull-request CI uses mocks and never calls the real Lark Webhook.

Lark group history is not the canonical secret store. Temporary access inclusion is a deliberate convenience tradeoff and should be disabled when the group membership is not sufficiently restricted.

## SSH fallback

DevSpace:

```bash
cat ~/private-runner-session/devspace/connection.txt
```

T3 Code:

```bash
cat ~/private-runner-session/t3code/connection.txt
```

These files remain mode `0600` and are removed during cleanup.

## Troubleshooting

### No messages are sent

Check:

1. `LARK_REPORTING_ENABLED` is exactly `true`.
2. `LARK_WEBHOOK_URL` and `LARK_WEBHOOK_SECRET` exist in the selected repository/Environment context.
3. The custom bot still belongs to the intended group.
4. Signature verification uses the matching current signing secret.
5. `$RUNNER_TEMP/private-runner-diagnostics/lark-webhook.log` for a stable error category.

### Lifecycle messages arrive but a service message is missing

A service notification is emitted only after that service passes its public readiness check. Inspect the existing private optional-service diagnostics and failure code:

```text
DevSpace public verification -> E54
T3 public verification       -> E63
```

A notification failure does not stop the service, so also check the private connection file through SSH.

### Temporary access is not included

Confirm `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS` is exactly `true`. Missing or malformed private access files are rejected. The reporter requires current-user ownership, private permissions, one-line values, and an expected value/URL shape.

### `offline` is missing

GitHub may terminate the hosted job before finalization executes. Treat the absolute `Expires` timestamp from earlier messages as authoritative for staleness.

### Rotate the Webhook

1. rotate or recreate the custom bot Webhook/signing secret in Lark;
2. replace both GitHub Secrets;
3. dispatch a new session;
4. confirm the new `starting` message;
5. revoke the previous Webhook if it was not already invalidated.

## Future extension

Issue #14 tracks optional official `lark-cli` IM and Lark Base backends. Those backends must reuse the normalized event contract and remain independent from the working Webhook path.

Potential future capabilities include private bot conversations, structured status history, and exact Base upserts. Base may store non-sensitive state and service URLs, but never DevSpace Owner Tokens, T3 Pairing URLs, or other credentials.
