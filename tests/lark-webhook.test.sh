#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTER="$ROOT_DIR/scripts/report-session-event.sh"
LIB="$ROOT_DIR/scripts/lib/session-event.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_json() {
  local path="$1"
  local expression="$2"
  python3 - "$path" "$expression" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)
if not eval(sys.argv[2], {"value": value}):
    raise SystemExit(1)
PY
}

file_mode() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])
PY
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export RUNNER_TEMP="$tmp/runner-temp"
mkdir -p "$HOME" "$RUNNER_TEMP" "$tmp/bin"

cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
printf '%s' "$payload" > "${MOCK_PAYLOAD:?}"
printf '%s\n' "${!#}" > "${MOCK_URL:?}"
printf '{"code":0,"msg":"success"}\n'
MOCK
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export MOCK_PAYLOAD="$tmp/payload.json"
export MOCK_URL="$tmp/url.txt"

export GITHUB_RUN_ID=123456
export GITHUB_RUN_ATTEMPT=2
export GITHUB_REPOSITORY=weavertech-group/runner
export GITHUB_SERVER_URL=https://github.com
export SESSION_TARGET_ID=repo-01
export SESSION_EVENT_NOW_EPOCH=1784600000
export LARK_WEBHOOK_URL=https://open.larksuite.com/open-apis/bot/v2/hook/test-hook
export LARK_WEBHOOK_SECRET=test-signing-secret

# Disabled reporting is a successful no-op and makes no HTTP request.
export LARK_REPORTING_ENABLED=false
output="$(bash "$REPORTER" starting 2>&1)" || fail 'disabled reporting failed'
[[ -z "$output" ]] || fail 'disabled reporting produced output'
[[ ! -e "$MOCK_PAYLOAD" ]] || fail 'disabled reporting called curl'

# Enabled reporting creates a correctly signed fixed text payload.
export LARK_REPORTING_ENABLED=true
output="$(bash "$REPORTER" starting 2>&1)" || fail 'starting report failed'
[[ -z "$output" ]] || fail 'successful reporting produced public output'
[[ "$(<"$MOCK_URL")" == "$LARK_WEBHOOK_URL" ]] || fail 'wrong webhook destination'
assert_json "$MOCK_PAYLOAD" 'value["timestamp"] == "1784600000"' || fail 'wrong timestamp'
assert_json "$MOCK_PAYLOAD" 'value["msg_type"] == "text"' || fail 'wrong message type'
assert_json "$MOCK_PAYLOAD" '"Runner starting" in value["content"]["text"]' || fail 'starting message missing'
assert_json "$MOCK_PAYLOAD" '"repo-01" in value["content"]["text"]' || fail 'opaque target missing'
assert_json "$MOCK_PAYLOAD" '"weavertech-group/runner/actions/runs/123456/attempts/2" in value["content"]["text"]' || fail 'Actions URL missing'
expected_sign="$(python3 - <<'PY'
import base64, hashlib, hmac
key=b"1784600000\ntest-signing-secret"
print(base64.b64encode(hmac.new(key, digestmod=hashlib.sha256).digest()).decode())
PY
)"
actual_sign="$(python3 - "$MOCK_PAYLOAD" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["sign"])
PY
)"
[[ "$actual_sign" == "$expected_sign" ]] || fail 'signature does not match Lark algorithm'

# Expiry is persisted once per run and reused across events.
expiry_first="$(<"$HOME/private-runner-session/lark-session-expiry")"
export SESSION_EVENT_NOW_EPOCH=1784600300
bash "$REPORTER" setup-ready >/dev/null 2>&1 || fail 'ready report failed'
expiry_second="$(<"$HOME/private-runner-session/lark-session-expiry")"
[[ "$expiry_first" == "$expiry_second" ]] || fail 'expiry changed within one session'
[[ "$(file_mode "$HOME/private-runner-session/lark-session-expiry")" == 600 ]] || \
  fail 'expiry file is not private'

# Service events support allowlisted services and use only the non-sensitive URL.
mkdir -p "$HOME/private-runner-session/devspace"
printf '%s\n' 'https://devspace-test.trycloudflare.com/mcp' > \
  "$HOME/private-runner-session/devspace/mcp-url"
printf '%s\n' 'fake-owner-token-must-not-leak' > \
  "$HOME/private-runner-session/devspace/owner-token"
chmod 0600 "$HOME/private-runner-session/devspace/mcp-url" \
  "$HOME/private-runner-session/devspace/owner-token"
export SESSION_SERVICE=devspace
bash "$REPORTER" service-online >/dev/null 2>&1 || fail 'DevSpace service report failed'
assert_json "$MOCK_PAYLOAD" '"DevSpace online" in value["content"]["text"]' || fail 'DevSpace message missing'
assert_json "$MOCK_PAYLOAD" '"https://devspace-test.trycloudflare.com/mcp" in value["content"]["text"]' || fail 'DevSpace URL missing'
if grep -Fq 'fake-owner-token-must-not-leak' "$MOCK_PAYLOAD"; then
  fail 'temporary Owner Token entered the foundation payload'
fi

# Generic event JSON contains an explicit field allowlist and no temporary access.
# shellcheck source=../scripts/lib/session-event.sh
source "$LIB"
session_event_build service-online || fail 'generic event build failed'
session_event_export
generic_json="$tmp/generic.json"
session_event_to_json > "$generic_json"
assert_json "$generic_json" 'set(value) == {"actions_url","error_code","event","expires_at","github_run_attempt","github_run_id","occurred_at","runner_name","service","service_online","service_url","session_key","setup_status","ssh_online","target_id"}' || \
  fail 'generic event field allowlist changed'
if grep -Eqi 'owner|pairing|token|secret|credential|authkey|password' "$generic_json"; then
  fail 'generic event JSON contains a secret-like field or value'
fi

# Unknown events and services are rejected before any request is sent.
rm -f "$MOCK_PAYLOAD"
if bash "$REPORTER" unknown-event >/dev/null 2>&1; then
  fail 'unknown event was accepted'
fi
[[ ! -e "$MOCK_PAYLOAD" ]] || fail 'unknown event reached Webhook'
export SESSION_SERVICE=unknown
if bash "$REPORTER" service-online >/dev/null 2>&1; then
  fail 'unknown service was accepted'
fi
[[ ! -e "$MOCK_PAYLOAD" ]] || fail 'unknown service reached Webhook'

for script in "$REPORTER" "$ROOT_DIR/scripts/lib/lark-webhook.sh" "$LIB"; do
  bash -n "$script" || fail "shell syntax failed: $script"
  if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$script"; then
    fail "reporting script can expose environment data: $script"
  fi
done

printf 'Lark Webhook foundation tests passed\n'
