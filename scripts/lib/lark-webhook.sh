#!/usr/bin/env bash

lark_webhook_enabled() {
  [[ "${LARK_REPORTING_ENABLED-false}" == true ]]
}

lark_webhook_validate_config() {
  [[ -n "${LARK_WEBHOOK_URL-}" && -n "${LARK_WEBHOOK_SECRET-}" ]] || return 1
  [[ "$LARK_WEBHOOK_URL" =~ ^https://[^[:space:]]+/open-apis/bot/v2/hook/[A-Za-z0-9_-]+$ ]] || return 1
  [[ "$LARK_WEBHOOK_SECRET" != *$'\n'* && "$LARK_WEBHOOK_SECRET" != *$'\r'* ]] || return 1
}

lark_webhook_temporary_access_enabled() {
  [[ "${LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS-false}" == true ]]
}

lark_webhook_service_access() {
  local value=''
  local expected_prefix=''

  case "$SE_SERVICE" in
    devspace)
      value="$(session_event_read_private_line "${HOME:?HOME is required}/private-runner-session/devspace/owner-token")" || return 1
      [[ "$value" =~ ^[a-f0-9]{64}$ ]] || return 1
      ;;
    t3code)
      value="$(session_event_read_private_line "${HOME:?HOME is required}/private-runner-session/t3code/pairing-url")" || return 1
      expected_prefix="${SE_SERVICE_URL%/}/pair#token="
      [[ "$value" == "$expected_prefix"* ]] || return 1
      [[ "${value#"$expected_prefix"}" =~ ^[^[:space:]#]{1,1024}$ ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  printf '%s\n' "$value"
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
      local temporary_access=''
      if lark_webhook_temporary_access_enabled; then
        temporary_access="$(lark_webhook_service_access)" || return 1
      fi
      case "$SE_SERVICE" in
        devspace)
          if [[ -n "$temporary_access" ]]; then
            printf 'DevSpace online\nTarget: %s\nMCP URL: %s\nOwner Token: %s\nTemporary access expires with this runner session.\nExpires: %s\nRun: %s' \
              "$SE_TARGET_ID" "$SE_SERVICE_URL" "$temporary_access" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          else
            printf 'DevSpace online\nTarget: %s\nMCP URL: %s\nOwner Token: available through SSH fallback\nExpires: %s\nRun: %s' \
              "$SE_TARGET_ID" "$SE_SERVICE_URL" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          fi
          ;;
        t3code)
          if [[ -n "$temporary_access" ]]; then
            printf 'T3 Code online\nTarget: %s\nT3 URL: %s\nPairing URL: %s\nTemporary access expires with this runner session.\nExpires: %s\nRun: %s' \
              "$SE_TARGET_ID" "$SE_SERVICE_URL" "$temporary_access" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          else
            printf 'T3 Code online\nTarget: %s\nT3 URL: %s\nPairing URL: available through SSH fallback\nExpires: %s\nRun: %s' \
              "$SE_TARGET_ID" "$SE_SERVICE_URL" "$SE_EXPIRES_AT" "$SE_ACTIONS_URL"
          fi
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
  lark_webhook_validate_config

  timestamp="${SESSION_EVENT_NOW_EPOCH-$(date -u +%s)}"
  [[ "$timestamp" =~ ^[0-9]{10}$ ]]
  signature="$(lark_webhook_signature "$timestamp")"
  message="$(lark_webhook_message)"
  payload="$(lark_webhook_payload "$timestamp" "$signature" "$message")"
  response_file="$(mktemp "${RUNNER_TEMP:-/tmp}/lark-webhook-response.XXXXXX")"
  chmod 0600 "$response_file"

  printf '%s' "$payload" | curl \
    --fail-with-body \
    --silent \
    --show-error \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    "$LARK_WEBHOOK_URL" \
    > "$response_file"
  lark_webhook_response_ok "$response_file"

  rm -f "$response_file"
}
