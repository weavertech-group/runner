# Lark reporting

The private runner can send signed lifecycle messages to a Lark custom-bot
Webhook. Setting only the Webhook URL is not enough.

## Required configuration

| Kind | Name | Value |
| --- | --- | --- |
| Repository variable | `LARK_REPORTING_ENABLED` | `true` |
| Repository secret | `LARK_WEBHOOK_URL` | Custom-bot Webhook URL (`.../open-apis/bot/v2/hook/...`) |
| Repository secret | `LARK_WEBHOOK_SECRET` | Custom-bot signing secret |

Optional repository variable:

| Kind | Name | Value |
| --- | --- | --- |
| Repository variable | `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS` | Set to `true` only when Lark may receive the T3 pairing URL. It is disabled by default, so pairing material remains only in SSH-readable private files. |

Secrets must be repository secrets (or present in the selected Environment). A
custom bot with signature verification enabled rejects unsigned payloads; this
repository always signs when reporting is enabled.

## Events

When reporting is enabled, the workflow sends signed text events:

- `starting`
- `ssh-online` (only when SSH is enabled)
- `setup-ready`
- `service-online` for T3 Code (includes the pairing URL only when
  `LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=true`)
- `offline`

Connection details are written only to mode-`0600` files under
`~/private-runner-session`. This is a public repository: pairing URLs, tokens,
private repository names, and service logs must never be printed to Actions
logs or step summaries.

Lark delivery is part of the happy path. HTTP and network failures raise the
native Python exception and fail the invoking workflow step. The script does not
interpret the business code in an otherwise successful HTTP response.
`scripts/report-lark.py` contains the small signing, event-text, and Webhook POST
needed by the workflow and uses only the Python standard library.
