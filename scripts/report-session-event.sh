#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/session-event.sh"
source "$ROOT_DIR/scripts/lib/lark-webhook.sh"

lark_webhook_enabled || exit 0
session_event_build "${1:?event is required}"
session_event_export
lark_webhook_send_event
