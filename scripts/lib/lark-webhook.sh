#!/usr/bin/env bash

lark_webhook_diagnostic() {
  local category="$1"
  local runner_temp="${RUNNER_TEMP:-/tmp}"
  local directory="$runner_temp/private-runner-diagnostics"
  local path="$directory/lark-webhook.log"

  install -d -m 0700 "$directory" 2>/dev/null || return 0
  umask 077
  printf '%s event=%s service=%s\n' \
    "$category" "${SE_EVENT-unknown}" "${SE_SERVICE-none}" >> "$path" 2>/dev/null || return 0
  chmod 0600 "$path" 2>/dev/null || true
}

lark_webhook_enabled() {
  [[ "${LARK_REPORTING_ENABLED-false}" == true ]]
}

lark_webhook_validate_config() {
  [[ -n "${LARK_WEBHOOK_URL-}" && -n "${LARK_WEBHOOK_SECRET-}" ]] || return 1
  [[ "$LARK_WEBHOOK_URL" =~ ^https://[^[:space:]]+/open-apis/bot/v2/hook/[A-Za-z0-9_-]+$ ]] || return 1
  [[ "$LARK_WEBHOOK_SECRET" != *$'\n'* && "$LARK_WEBHOOK_SECRET" != *$'\r'* ]] || return 1
}

lark_webhook_message() {
  case "$SE_EVENT" in
    starting)
      printf 'Runner starting\nTarget: %s\nSetup: installing\nSSH: pending or disabled\nExpires: %s\nRun: %s' \
        "$SE_TARGET_ID" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
      ;;
    ssh-online)
      printf 'Runner SSH online\nTarget: %s\nSetup: %s\nSSH: online\nRunner: %s\nExpires: %s\nRun: %s' \
        "$SE_TARGET_ID" "$SE_SETUP_STATUS" "${SE_RUNNER_NAME:-unknown}" \
        "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
      ;;
    setup-ready)
      printf 'Runner ready\nTarget: %s\nSetup: ready\nSSH: %s\nExpires: %s\nRun: %s' \
        "$SE_TARGET_ID" "$SE_SSH_ONLINE" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
      ;;
    setup-degraded)
      printf 'Runner degraded\nTarget: %s\nSetup: degraded\nSSH: %s\nStatus code: %s\nExpires: %s\nRun: %s' \
        "$SE_TARGET_ID" "$SE_SSH_ONLINE" "${SE_ERROR_CODE:-setup-degraded}" \
        "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
      ;;
    service-online)
      case "$SE_SERVICE" in
        devspace)
          printf 'DevSpace online\nTarget: %s\nMCP URL: %s\nTemporary access: available through SSH fallback\nExpires: %s\nRun: %s' \
            "$SE_TARGET_ID" "$SE_SERVICE_URL" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          ;;
        t3code)
          printf 'T3 Code online\nTarget: %s\nT3 URL: %s\nTemporary access: available through SSH fallback\nExpires: %s\nRun: %s' \
            "$SE_TARGET_ID" "$SE_SERVICE_URL" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    offline)
      printf 'Runner offline\nTarget: %s\nSSH: offline\nEnded: %s\nRun: %s' \
        "$SE_TARGET_ID" "$SE_OCCURRED_AT" "$SE_ACTIONS_URL"
      ;;
    *)
      return 1
      ;;
  esac
}

lark_webhook_signature() {
  local timestamp="$1"
  python3 - "$timestamp" "$LARK_WEBHOOK_SECRET" <<'PY'
import base64
import hashlib
import hmac
import sys

timestamp, secret = sys.argv[1], sys.argv[2]
string_to_sign = f"{timestamp}\n{secret}".encode("utf-8")
signature = hmac.new(string_to_sign, digestmod=hashlib.sha256).digest()
print(base64.b64encode(signature).decode("ascii"))
PY
}

lark_webhook_payload() {
  local timestamp="$1"
  local signature="$2"
  local message="$3"
  python3 - "$timestamp" "$signature" "$message" <<'PY'
import json
import sys

print(json.dumps({
    "timestamp": sys.argv[1],
    "sign": sys.argv[2],
    "msg_type": "text",
    "content": {"text": sys.argv[3]},
}, separators=(",", ":")))
PY
}

lark_webhook_response_ok() {
  local path="$1"
  python3 - "$path" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        response = json.load(handle)
except Exception:
    raise SystemExit(1)

if response.get("code") == 0 or response.get("StatusCode") == 0:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

lark_webhook_send_event() {
  local timestamp=''
  local signature=''
  local message=''
  local payload=''
  local response_file=''

  lark_webhook_enabled || return 0
  if ! lark_webhook_validate_config; then
    lark_webhook_diagnostic configuration-error
    return 1
  fi

  timestamp="${SESSION_EVENT_NOW_EPOCH-$(date -u +%s)}"
  [[ "$timestamp" =~ ^[0-9]{10}$ ]] || {
    lark_webhook_diagnostic timestamp-error
    return 1
  }
  signature="$(lark_webhook_signature "$timestamp")" || {
    lark_webhook_diagnostic signature-error
    return 1
  }
  message="$(lark_webhook_message)" || {
    lark_webhook_diagnostic message-error
    return 1
  }
  payload="$(lark_webhook_payload "$timestamp" "$signature" "$message")" || {
    lark_webhook_diagnostic payload-error
    return 1
  }

  response_file="$(mktemp "${RUNNER_TEMP:-/tmp}/lark-webhook-response.XXXXXX")" || {
    lark_webhook_diagnostic response-file-error
    return 1
  }
  chmod 0600 "$response_file"

  if ! printf '%s' "$payload" | curl \
      --fail-with-body \
      --silent \
      --show-error \
      --connect-timeout 5 \
      --max-time 15 \
      --retry 2 \
      --retry-delay 1 \
      --retry-all-errors \
      --header 'Content-Type: application/json' \
      --data-binary @- \
      "$LARK_WEBHOOK_URL" \
      > "$response_file" 2>/dev/null; then
    rm -f "$response_file"
    lark_webhook_diagnostic transport-error
    return 1
  fi

  if ! lark_webhook_response_ok "$response_file"; then
    rm -f "$response_file"
    lark_webhook_diagnostic api-error
    return 1
  fi

  rm -f "$response_file"
  return 0
}
