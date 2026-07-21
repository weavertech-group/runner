#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTER="$ROOT_DIR/scripts/report-session-event.sh"
CLEANUP="$ROOT_DIR/scripts/cleanup.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

request_count() {
  if [[ -r "$MOCK_COUNT" ]]; then
    cat "$MOCK_COUNT"
  else
    printf '0\n'
  fi
}

latest_message() {
  python3 - "$MOCK_LATEST_PAYLOAD" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["content"]["text"])
PY
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export RUNNER_TEMP="$tmp/runner-temp"
mkdir -p "$HOME/private-runner-session/devspace" \
  "$HOME/private-runner-session/t3code" "$RUNNER_TEMP" "$tmp/bin"

cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
count=0
if [[ -r "${MOCK_COUNT:?}" ]]; then
  count="$(<"$MOCK_COUNT")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$MOCK_COUNT"
printf '%s' "$payload" > "${MOCK_PAYLOAD_DIR:?}/payload-${count}.json"
printf '%s' "$payload" > "${MOCK_LATEST_PAYLOAD:?}"
if [[ "${MOCK_CURL_MODE-success}" == fail ]]; then
  exit 22
fi
printf '{"code":0,"msg":"success"}\n'
MOCK
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export MOCK_COUNT="$tmp/request-count"
export MOCK_PAYLOAD_DIR="$tmp/payloads"
export MOCK_LATEST_PAYLOAD="$tmp/latest-payload.json"
mkdir -p "$MOCK_PAYLOAD_DIR"

export GITHUB_RUN_ID=789012
export GITHUB_RUN_ATTEMPT=3
export GITHUB_REPOSITORY=weavertech-group/runner
export GITHUB_SERVER_URL=https://github.com
export SESSION_TARGET_ID=repo-01
export SESSION_SSH_ONLINE=true
export SESSION_EVENT_NOW_EPOCH=1784600000
export LARK_WEBHOOK_URL=https://open.larksuite.com/open-apis/bot/v2/hook/test-hook
export LARK_WEBHOOK_SECRET=test-signing-secret
export LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=true

printf 'ready\n' > "$HOME/private-runner-session/setup-status"
printf 'development_install=success\n' > "$HOME/private-runner-session/setup-details"
printf 'https://dev-mvp.trycloudflare.com/mcp\n' > "$HOME/private-runner-session/devspace/mcp-url"
printf '%064d\n' 0 | tr '0' 'b' > "$HOME/private-runner-session/devspace/owner-token"
printf 'https://t3-mvp.trycloudflare.com\n' > "$HOME/private-runner-session/t3code/t3-url"
printf 'https://t3-mvp.trycloudflare.com/pair#token=mvp_pairing-token.1\n' > \
  "$HOME/private-runner-session/t3code/pairing-url"
chmod 0600 "$HOME/private-runner-session/setup-status" \
  "$HOME/private-runner-session/setup-details" \
  "$HOME/private-runner-session/devspace/mcp-url" \
  "$HOME/private-runner-session/devspace/owner-token" \
  "$HOME/private-runner-session/t3code/t3-url" \
  "$HOME/private-runner-session/t3code/pairing-url"

# Disabled reporting creates neither an HTTP request nor delivery state.
export LARK_REPORTING_ENABLED=false
bash "$REPORTER" starting >/dev/null 2>&1 || fail 'disabled reporting failed caller'
[[ "$(request_count)" -eq 0 ]] || fail 'disabled reporting made a request'
[[ ! -e "$HOME/private-runner-session/lark-events" ]] || fail 'disabled reporting created markers'
[[ ! -e "$HOME/private-runner-session/lark-session-active" ]] || fail 'disabled reporting activated a session'

# always() status steps after a preflight failure must not create synthetic Lark
# lifecycle messages. Only the workflow's starting event activates reporting.
export LARK_REPORTING_ENABLED=true
bash "$REPORTER" setup-degraded >/dev/null 2>&1 || fail 'preflight degraded gate failed caller'
bash "$REPORTER" offline >/dev/null 2>&1 || fail 'preflight offline gate failed caller'
[[ "$(request_count)" -eq 0 ]] || fail 'preflight failure emitted a false lifecycle message'
[[ ! -e "$HOME/private-runner-session/lark-events" ]] || fail 'preflight failure created delivery markers'
[[ ! -e "$HOME/private-runner-session/lark-session-expiry" ]] || fail 'preflight failure created expiry state'

# A successful starting invocation activates the session, is marked delivered,
# and routine retries do not resend it.
bash "$REPORTER" starting >/dev/null 2>&1 || fail 'starting event failed caller'
[[ "$(request_count)" -eq 1 ]] || fail 'starting event was not sent once'
active_marker="$HOME/private-runner-session/lark-session-active"
[[ -f "$active_marker" && "$(<"$active_marker")" == active ]] || \
  fail 'starting event did not activate Lark lifecycle reporting'
[[ "$(stat -c '%a' "$active_marker")" == 600 ]] || fail 'active marker is not private'
marker_dir="$HOME/private-runner-session/lark-events"
starting_marker="$marker_dir/webhook-starting"
[[ -f "$starting_marker" && "$(<"$starting_marker")" == delivered ]] || \
  fail 'successful starting event was not marked'
[[ "$(stat -c '%a' "$marker_dir")" == 700 ]] || fail 'marker directory is not private'
[[ "$(stat -c '%a' "$starting_marker")" == 600 ]] || fail 'marker file is not private'
bash "$REPORTER" starting >/dev/null 2>&1 || fail 'duplicate starting event failed caller'
[[ "$(request_count)" -eq 1 ]] || fail 'successful starting event was duplicated'

# Failed delivery is not marked and remains retryable.
export SESSION_EVENT_NOW_EPOCH=1784600300
export MOCK_CURL_MODE=fail
output="$(bash "$REPORTER" ssh-online 2>&1)" || fail 'failed Webhook affected caller'
[[ -z "$output" ]] || fail 'failed Webhook produced public output'
[[ "$(request_count)" -eq 2 ]] || fail 'failed SSH event was not attempted'
[[ ! -e "$marker_dir/webhook-ssh-online" ]] || fail 'failed SSH event was marked delivered'
export MOCK_CURL_MODE=success
bash "$REPORTER" ssh-online >/dev/null 2>&1 || fail 'SSH retry failed caller'
[[ "$(request_count)" -eq 3 ]] || fail 'failed SSH event was not retried'
[[ -f "$marker_dir/webhook-ssh-online" ]] || fail 'successful SSH retry was not marked'
bash "$REPORTER" ssh-online >/dev/null 2>&1
[[ "$(request_count)" -eq 3 ]] || fail 'successful SSH retry was duplicated'

# Ready and degraded results are mutually exclusive after one succeeds.
bash "$REPORTER" setup-ready >/dev/null 2>&1 || fail 'ready event failed caller'
[[ "$(request_count)" -eq 4 ]] || fail 'ready event was not sent'
bash "$REPORTER" setup-degraded >/dev/null 2>&1 || fail 'degraded counterpart failed caller'
[[ "$(request_count)" -eq 4 ]] || fail 'mutually exclusive setup result was sent'
[[ -f "$marker_dir/webhook-setup-ready" ]] || fail 'ready marker missing'
[[ ! -e "$marker_dir/webhook-setup-degraded" ]] || fail 'degraded marker should not exist'

# Service markers and credentials remain isolated per service.
SESSION_SERVICE=devspace bash "$REPORTER" service-online >/dev/null 2>&1 || \
  fail 'DevSpace event failed caller'
[[ "$(request_count)" -eq 5 ]] || fail 'DevSpace event was not sent'
devspace_message="$(latest_message)"
grep -Fq "Owner Token: $(<"$HOME/private-runner-session/devspace/owner-token")" \
  <<< "$devspace_message" || fail 'DevSpace temporary access missing under opt-in'
if grep -Fq '#token=' <<< "$devspace_message"; then fail 'T3 access leaked into DevSpace'; fi

SESSION_SERVICE=t3code bash "$REPORTER" service-online >/dev/null 2>&1 || \
  fail 'T3 event failed caller'
[[ "$(request_count)" -eq 6 ]] || fail 'T3 event was not sent'
t3_message="$(latest_message)"
grep -Fq "Pairing URL: $(<"$HOME/private-runner-session/t3code/pairing-url")" \
  <<< "$t3_message" || fail 'T3 temporary access missing under opt-in'
if grep -Fq "$(<"$HOME/private-runner-session/devspace/owner-token")" <<< "$t3_message"; then
  fail 'DevSpace access leaked into T3'
fi

SESSION_SERVICE=devspace bash "$REPORTER" service-online >/dev/null 2>&1
SESSION_SERVICE=t3code bash "$REPORTER" service-online >/dev/null 2>&1
[[ "$(request_count)" -eq 6 ]] || fail 'service events did not deduplicate independently'
[[ -f "$marker_dir/webhook-service-online-devspace" ]] || fail 'DevSpace marker missing'
[[ -f "$marker_dir/webhook-service-online-t3code" ]] || fail 'T3 marker missing'

# Every marker stores only the non-sensitive delivery state.
while IFS= read -r marker; do
  [[ "$(stat -c '%a' "$marker")" == 600 ]] || fail "marker is not private: $marker"
  [[ "$(<"$marker")" == delivered ]] || fail "marker contains unexpected state: $marker"
done < <(find "$marker_dir" -maxdepth 1 -type f -print)
if grep -R -E 'trycloudflare|Owner|Pairing|token=|signing-secret' "$marker_dir" >/dev/null; then
  fail 'delivery markers contain sensitive or message data'
fi

# One persisted expiry is reused despite later event timestamps.
expiry_epoch="$(<"$HOME/private-runner-session/lark-session-expiry")"
[[ "$expiry_epoch" -eq 1784621600 ]] || fail 'unexpected persisted expiry'
expected_expiry="$(date -u -d "@$expiry_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
for payload in "$MOCK_PAYLOAD_DIR"/payload-{1,3,4,5,6}.json; do
  grep -Fq "$expected_expiry" "$payload" || fail "expiry changed across events: $payload"
done

# Offline sends no prior access material and is independently deduplicated.
unset SESSION_SERVICE
bash "$REPORTER" offline >/dev/null 2>&1 || fail 'offline event failed caller'
[[ "$(request_count)" -eq 7 ]] || fail 'offline event was not sent'
offline_message="$(latest_message)"
if grep -E -q 'Owner Token|Pairing URL|trycloudflare|#token=' <<< "$offline_message"; then
  fail 'offline message repeated service access material'
fi
bash "$REPORTER" offline >/dev/null 2>&1
[[ "$(request_count)" -eq 7 ]] || fail 'offline event was duplicated'

# Cleanup removes all local connection, setup, activation, and delivery state.
printf 'response\n' > "$RUNNER_TEMP/lark-webhook-response.leftover"
bash "$CLEANUP" >/dev/null 2>&1 || fail 'cleanup failed'
[[ ! -e "$marker_dir" ]] || fail 'cleanup did not remove Lark markers'
[[ ! -e "$HOME/private-runner-session/lark-session-expiry" ]] || fail 'cleanup did not remove expiry'
[[ ! -e "$active_marker" ]] || fail 'cleanup did not remove active marker'
[[ ! -e "$HOME/private-runner-session/setup-status" ]] || fail 'cleanup did not remove setup status'
[[ ! -e "$HOME/private-runner-session/setup-details" ]] || fail 'cleanup did not remove setup details'
[[ ! -e "$HOME/private-runner-session/devspace" ]] || fail 'cleanup did not remove DevSpace connection data'
[[ ! -e "$HOME/private-runner-session/t3code" ]] || fail 'cleanup did not remove T3 connection data'
[[ ! -e "$RUNNER_TEMP/lark-webhook-response.leftover" ]] || fail 'cleanup did not remove response temp files'

bash -n "$REPORTER" "$CLEANUP" || fail 'MVP script syntax failed'
printf 'Lark Webhook MVP tests passed\n'
