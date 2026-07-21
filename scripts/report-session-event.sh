#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/session-event.sh
source "$ROOT_DIR/scripts/lib/session-event.sh"
# shellcheck source=scripts/lib/lark-webhook.sh
source "$ROOT_DIR/scripts/lib/lark-webhook.sh"

lark_delivery_directory() {
  printf '%s/private-runner-session/lark-events\n' "${HOME:?HOME is required}"
}

lark_delivery_prepare_directory() {
  local directory=''
  directory="$(lark_delivery_directory)" || return 1
  if [[ ! -e "$directory" ]]; then
    install -d -m 0700 "$directory" || return 1
  fi
  [[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || return 1
  chmod 0700 "$directory" || return 1
}

lark_delivery_marker_name() {
  case "$SE_EVENT" in
    service-online)
      session_event_validate_service "$SE_SERVICE" || return 1
      printf 'webhook-service-online-%s\n' "$SE_SERVICE"
      ;;
    starting|ssh-online|setup-ready|setup-degraded|offline)
      printf 'webhook-%s\n' "$SE_EVENT"
      ;;
    *)
      return 1
      ;;
  esac
}

lark_delivery_marker_path() {
  local marker_name=''
  marker_name="$(lark_delivery_marker_name)" || return 1
  printf '%s/%s\n' "$(lark_delivery_directory)" "$marker_name"
}

lark_delivery_marker_exists() {
  local path="$1"
  local value=''
  value="$(session_event_read_private_line "$path" 2>/dev/null)" || return 1
  [[ "$value" == delivered ]]
}

lark_delivery_already_delivered() {
  local marker=''
  marker="$(lark_delivery_marker_path)" || return 1
  lark_delivery_marker_exists "$marker"
}

lark_delivery_setup_result_already_delivered() {
  local counterpart=''
  case "$SE_EVENT" in
    setup-ready)
      counterpart="$(lark_delivery_directory)/webhook-setup-degraded"
      ;;
    setup-degraded)
      counterpart="$(lark_delivery_directory)/webhook-setup-ready"
      ;;
    *)
      return 1
      ;;
  esac
  lark_delivery_marker_exists "$counterpart"
}

lark_delivery_mark_delivered() {
  local directory=''
  local marker=''
  local temporary=''

  lark_delivery_prepare_directory || return 1
  directory="$(lark_delivery_directory)" || return 1
  marker="$(lark_delivery_marker_path)" || return 1
  temporary="$(mktemp "$directory/.delivery.XXXXXX")" || return 1
  umask 077
  if ! printf 'delivered\n' > "$temporary" || ! chmod 0600 "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  mv -f "$temporary" "$marker" || {
    rm -f "$temporary"
    return 1
  }
  chmod 0600 "$marker" || return 1
}

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

# Successful delivery is recorded privately so ordinary workflow retries do not
# resend the same message. Failed delivery is not marked and remains retryable.
if lark_delivery_already_delivered; then
  exit 0
fi
if lark_delivery_setup_result_already_delivered; then
  lark_webhook_diagnostic setup-result-already-delivered
  exit 0
fi

if lark_webhook_send_event; then
  lark_delivery_mark_delivered || lark_webhook_diagnostic marker-error
fi

# Lark reporting is deliberately best effort. Configuration, transport, remote
# API, and local marker failures never fail the runner session.
exit 0
