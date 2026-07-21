# Lark reporting

The reporting architecture is Webhook-first and keeps the runner workflow independent from Lark request formats:

```text
runner lifecycle or service state
  -> normalized session event
  -> scripts/report-session-event.sh
  -> signed Lark custom-bot Webhook
```

The initial backend sends one-way notifications to one fixed private Lark group. Future `lark-cli` IM or Lark Base backends can consume the same non-sensitive event model without replacing workflow lifecycle calls.

## Current configuration contract

Create a Lark custom bot in a restricted internal group and enable signature verification. Store the resulting values as GitHub Repository Secrets:

```text
LARK_WEBHOOK_URL
LARK_WEBHOOK_SECRET
```

Configure GitHub Repository Variables:

```text
LARK_REPORTING_ENABLED=true
LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=false
```

The Webhook URL is a credential, not ordinary configuration. Do not put either Webhook value in workflow inputs, repository files, logs, artifacts, or caches.

`LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS` is reserved for the optional-service integration. It defaults to `false`. The event-model foundation never places DevSpace Owner Tokens, T3 Pairing URLs, or raw pairing tokens in generic event data.

## Event contract

The reporter accepts only:

```text
starting
ssh-online
setup-ready
setup-degraded
service-online
offline
```

`service-online` additionally requires `SESSION_SERVICE` to be one of:

```text
devspace
t3code
```

Generic event fields are limited to session/run metadata, opaque target ID, setup/SSH state, an allowlisted service name, its non-sensitive public URL, timestamps, expiry, runner name, and a non-sensitive error code.

Workflow code must call:

```bash
scripts/report-session-event.sh <event>
```

It must not construct Webhook payloads or signatures directly.

## Authentication and signing

The backend follows the Lark custom-bot signing contract:

1. Use the current Unix timestamp in seconds.
2. Form `timestamp + "\n" + signing secret`.
3. Use that string as the HMAC-SHA256 key for an empty message.
4. Base64-encode the digest.
5. Send `timestamp`, `sign`, `msg_type`, and `content` in the JSON body.

No Lark App ID, App Secret, OAuth login, access token, or `@larksuite/cli` installation is required for the Webhook MVP.

## Failure behavior

Reporting is optional and best effort:

- disabled reporting exits successfully without an external request;
- invalid configuration, network failure, or Lark API failure does not affect SSH, setup, optional services, the long-running session, or cleanup;
- retries are bounded and short;
- diagnostics contain stable non-sensitive categories only and are stored under `$RUNNER_TEMP/private-runner-diagnostics` with private permissions;
- diagnostics are not intended for public artifacts.

The privileged workflow remains manually dispatched, and pull-request CI uses mocked HTTP behavior rather than real Lark credentials.

## Current implementation status

The shared event model and signed Webhook backend are introduced by issue #11. Workflow lifecycle integration, optional-service access notifications, deduplication, cleanup integration, and final operator instructions are delivered by subsequent issues in the parent Epic.
