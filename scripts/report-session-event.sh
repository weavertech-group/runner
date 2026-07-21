#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/session-event.sh
source "$ROOT_DIR/scripts/lib/session-event.sh"
# shellcheck source=scripts/lib/lark-webhook.sh
source "$ROOT_DIR/scripts/lib/lark-webhook.sh"

event="${1-}"
if ! session_event_validate_event "$event"; then
  printf 'E70\n' >&2
  exit 64
fi

if ! lark_webhook_enabled; then
  exit 0
fi

if session_event_build "$event"; then
  :
else
  result=$?
  lark_webhook_diagnostic event-error
  if [[ "$result" -eq 64 ]]; then
    printf 'E70\n' >&2
    exit 64
  fi
  exit 0
fi
session_event_export

# Lark reporting is deliberately best effort. The caller receives success even
# when configuration, transport, or the remote API is unavailable.
lark_webhook_send_event || true
