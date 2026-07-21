#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
REPORTER="$ROOT_DIR/scripts/report-session-event.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

message_text() {
  python3 - "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["content"]["text"])
PY
}

reset_delivery_state() {
  rm -rf "$HOME/private-runner-session/lark-events"
  rm -f "$MOCK_PAYLOAD"
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
cat > "${MOCK_PAYLOAD:?}"
printf '{"code":0,"msg":"success"}\n'
MOCK
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export MOCK_PAYLOAD="$tmp/payload.json"

export GITHUB_RUN_ID=456789
export GITHUB_RUN_ATTEMPT=1
export GITHUB_REPOSITORY=weavertech-group/runner
export GITHUB_SERVER_URL=https://github.com
export SESSION_TARGET_ID=repo-01
export SESSION_SSH_ONLINE=true
export SESSION_EVENT_NOW_EPOCH=1784600000
export LARK_REPORTING_ENABLED=true
export LARK_WEBHOOK_URL=https://open.larksuite.com/open-apis/bot/v2/hook/test-hook
export LARK_WEBHOOK_SECRET=test-signing-secret

printf 'ready\n' > "$HOME/private-runner-session/setup-status"
printf 'https://dev-test.trycloudflare.com/mcp\n' > "$HOME/private-runner-session/devspace/mcp-url"
printf '%064d\n' 0 | tr '0' 'a' > "$HOME/private-runner-session/devspace/owner-token"
printf 'https://t3-test.trycloudflare.com\n' > "$HOME/private-runner-session/t3code/t3-url"
printf 'https://t3-test.trycloudflare.com/pair#token=test_pairing-token.1\n' > \
  "$HOME/private-runner-session/t3code/pairing-url"
chmod 0600 "$HOME/private-runner-session/setup-status" \
  "$HOME/private-runner-session/devspace/mcp-url" \
  "$HOME/private-runner-session/devspace/owner-token" \
  "$HOME/private-runner-session/t3code/t3-url" \
  "$HOME/private-runner-session/t3code/pairing-url"

# Temporary access is omitted by default for both services.
unset LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS
SESSION_SERVICE=devspace bash "$REPORTER" service-online >/dev/null 2>&1
text="$(message_text "$MOCK_PAYLOAD")"
grep -Fq 'MCP URL: https://dev-test.trycloudflare.com/mcp' <<< "$text" || fail 'DevSpace URL missing'
grep -Fq 'Owner Token: available through SSH fallback' <<< "$text" || fail 'DevSpace fallback missing'
if grep -Fq "$(<"$HOME/private-runner-session/devspace/owner-token")" <<< "$text"; then
  fail 'DevSpace token was sent without opt-in'
fi

SESSION_SERVICE=t3code bash "$REPORTER" service-online >/dev/null 2>&1
text="$(message_text "$MOCK_PAYLOAD")"
grep -Fq 'T3 URL: https://t3-test.trycloudflare.com' <<< "$text" || fail 'T3 URL missing'
grep -Fq 'Pairing URL: available through SSH fallback' <<< "$text" || fail 'T3 fallback missing'
if grep -Fq '#token=' <<< "$text"; then
  fail 'T3 pairing URL was sent without opt-in'
fi

# Reset successful markers to exercise the explicit opt-in formatting path.
reset_delivery_state
export LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS=true
SESSION_SERVICE=devspace bash "$REPORTER" service-online >/dev/null 2>&1
text="$(message_text "$MOCK_PAYLOAD")"
grep -Fq "Owner Token: $(<"$HOME/private-runner-session/devspace/owner-token")" <<< "$text" || \
  fail 'opted-in DevSpace token missing'
if grep -Fq '#token=' <<< "$text"; then fail 'T3 access leaked into DevSpace message'; fi

SESSION_SERVICE=t3code bash "$REPORTER" service-online >/dev/null 2>&1
text="$(message_text "$MOCK_PAYLOAD")"
grep -Fq "Pairing URL: $(<"$HOME/private-runner-session/t3code/pairing-url")" <<< "$text" || \
  fail 'opted-in T3 pairing URL missing'
if grep -Fq "$(<"$HOME/private-runner-session/devspace/owner-token")" <<< "$text"; then
  fail 'DevSpace access leaked into T3 message'
fi

# A pairing URL from another origin is rejected without public output or a request.
reset_delivery_state
printf 'https://other.trycloudflare.com/pair#token=wrong-origin\n' > \
  "$HOME/private-runner-session/t3code/pairing-url"
chmod 0600 "$HOME/private-runner-session/t3code/pairing-url"
output="$(SESSION_SERVICE=t3code bash "$REPORTER" service-online 2>&1)" || \
  fail 'invalid temporary access failed the runner caller'
[[ -z "$output" ]] || fail 'invalid temporary access produced public output'
[[ ! -e "$MOCK_PAYLOAD" ]] || fail 'invalid T3 pairing URL reached Webhook'

# Workflow reports each verified service independently and keeps the policy fixed.
report_block="$(sed -n '/- name: Report optional services online/,/- name: Validate public optional services/p' "$WORKFLOW")"
grep -Fq 'LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS: ${{ vars.LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS }}' \
  <<< "$report_block" || fail 'temporary-access policy is not repository configuration'
grep -Fq 'SESSION_SERVICE=devspace bash scripts/report-session-event.sh service-online' \
  <<< "$report_block" || fail 'DevSpace service event missing'
grep -Fq 'SESSION_SERVICE=t3code bash scripts/report-session-event.sh service-online' \
  <<< "$report_block" || fail 'T3 service event missing'
grep -Fq 'DEVSPACE_PUBLIC_VERIFY" == success' <<< "$report_block" || \
  fail 'DevSpace notification is not guarded by verification'
grep -Fq 'T3CODE_PUBLIC_VERIFY" == success' <<< "$report_block" || \
  fail 'T3 notification is not guarded by verification'

if grep -Fq 'LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS:' \
    <(sed -n '/workflow_dispatch:/,/run-name:/p' "$WORKFLOW"); then
  fail 'temporary-access delivery must not be a public workflow input'
fi

verify_dev_line="$(grep -n -- '- name: Verify public DevSpace' "$WORKFLOW" | cut -d: -f1)"
verify_t3_line="$(grep -n -- '- name: Verify public T3 Code' "$WORKFLOW" | cut -d: -f1)"
report_line="$(grep -n -- '- name: Report optional services online' "$WORKFLOW" | cut -d: -f1)"
[[ "$verify_dev_line" -lt "$report_line" && "$verify_t3_line" -lt "$report_line" ]] || \
  fail 'service notifications must follow public verification'

printf 'Lark optional-service tests passed\n'
