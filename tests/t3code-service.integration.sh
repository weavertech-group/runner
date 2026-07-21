#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
TARGET_WORKSPACE="${RUNNER_TEMP:?RUNNER_TEMP is required}/target-workspace"
SESSION_DIR="${HOME:?HOME is required}/private-runner-session"
CONNECTION_DIR="$SESSION_DIR/t3code"
DELIVERY_MARKER="$SESSION_DIR/lark-events/webhook-service-online-t3code"

cleanup() {
  HOME="$HOME" RUNNER_TEMP="$RUNNER_TEMP" bash "$CLEANUP_SCRIPT" >/dev/null 2>&1 || true
  npm uninstall --global t3 >/dev/null 2>&1 || true
}
trap cleanup EXIT

[[ "${LARK_REPORTING_ENABLED-}" == true ]]
[[ "${LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS-}" == true ]]
[[ -n "${LARK_WEBHOOK_URL-}" && -n "${LARK_WEBHOOK_SECRET-}" ]]

rm -rf "$TARGET_WORKSPACE"
git clone --quiet --no-hardlinks "$ROOT_DIR" "$TARGET_WORKSPACE"

bash "$ROOT_DIR/scripts/install-cloudflared.sh"
bash "$ROOT_DIR/scripts/install-t3code.sh"

ENABLE_DEVSPACE=false ENABLE_T3CODE=true \
  bash "$ROOT_DIR/scripts/start-quick-tunnels.sh"
bash "$ROOT_DIR/scripts/start-t3code.sh"
ENABLE_DEVSPACE=false ENABLE_T3CODE=true \
  bash "$ROOT_DIR/scripts/verify-public-services.sh"

install -d -m 0700 "$SESSION_DIR"
printf 'ready\n' > "$SESSION_DIR/setup-status"
chmod 0600 "$SESSION_DIR/setup-status"

SESSION_TARGET_ID=repo-01-pr-validation \
SESSION_SERVICE=t3code \
SESSION_SSH_ONLINE=true \
  bash "$ROOT_DIR/scripts/report-session-event.sh" service-online

[[ -f "$DELIVERY_MARKER" && ! -L "$DELIVERY_MARKER" ]]
[[ "$(stat -c '%a' "$DELIVERY_MARKER")" == 600 ]]
[[ "$(<"$DELIVERY_MARKER")" == delivered ]]

for path in "$CONNECTION_DIR/t3-url" "$CONNECTION_DIR/pairing-url" "$CONNECTION_DIR/connection.txt"; do
  [[ -f "$path" && ! -L "$path" ]]
  [[ "$(stat -c '%a' "$path")" == 600 ]]
done

t3_url="$(<"$CONNECTION_DIR/t3-url")"
pairing_url="$(<"$CONNECTION_DIR/pairing-url")"
[[ "$t3_url" =~ ^https://[-a-z0-9]+[.]trycloudflare[.]com$ ]]
[[ "$pairing_url" == "$t3_url"/pair#token=* ]]

printf 'real T3 tunnel and Lark integration test passed\n'
