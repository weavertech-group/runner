# Lark reporting

The private runner can send signed lifecycle messages to a Lark custom-bot
Webhook. Set these repository secrets to enable it:

```text
LARK_WEBHOOK_URL
LARK_WEBHOOK_SECRET
```

Set the repository variable `LARK_REPORTING_ENABLED=true`. The workflow sends
`starting`, `ssh-online`, `setup-ready`, and `offline` events. Connection details remain in the runner's private
`~/private-runner-session` files.

Lark delivery is part of the happy path: when reporting is enabled, invalid
configuration or a failed delivery fails the invoking workflow step with the
native command result. The scripts contain the signing and event-format logic
so the workflow itself never handles a webhook secret or constructs a payload.
