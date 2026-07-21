#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START_SCRIPT="$ROOT_DIR/scripts/start-cloudflare-tunnel.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-public-services.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
TEMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TEMP_ROOT/bin"
MOCK_HOME="$TEMP_ROOT/home"
MOCK_RUNNER_TEMP="$TEMP_ROOT/runner-temp"
TOKEN='cloudflare-tunnel-token'
T3_URL='https://t3-repo-07.example.com'
DEVSPACE_URL='https://mcp-repo-07.example.com'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  HOME="$MOCK_HOME" RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
    bash "$CLEANUP_SCRIPT" >/dev/null 2>&1 || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$MOCK_HOME" \
  "$MOCK_RUNNER_TEMP/private-runner-tools"

cat > "$MOCK_RUNNER_TEMP/private-runner-tools/cloudflared" <<'MOCK'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do sleep 10; done
MOCK

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$MOCK_BIN/node" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod 0755 "$MOCK_BIN"/* "$MOCK_RUNNER_TEMP/private-runner-tools/cloudflared"

stdout_file="$TEMP_ROOT/stdout"
stderr_file="$TEMP_ROOT/stderr"
PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
CLOUDFLARED_STARTUP_GRACE_SECONDS=0 \
CLOUDFLARE_TUNNEL_TOKEN="$TOKEN" \
DEVSPACE_PUBLIC_URL="$DEVSPACE_URL" \
ENABLE_DEVSPACE=true \
ENABLE_T3CODE=true \
T3_PUBLIC_URL="$T3_URL" \
  bash "$START_SCRIPT" >"$stdout_file" 2>"$stderr_file"

pid_file="$MOCK_RUNNER_TEMP/private-runner-diagnostics/cloudflared.pid"
token_file="$MOCK_RUNNER_TEMP/private-runner-diagnostics/cloudflared-token"
[[ -f "$pid_file" ]] || fail 'cloudflared PID file was not created'
[[ -f "$token_file" ]] || fail 'cloudflared token file was not created'
[[ "$(stat -c '%a' "$token_file")" == '600' ]] || \
  fail 'cloudflared token file permissions are not private'
[[ "$(cat "$token_file")" == "$TOKEN" ]] || fail 'cloudflared token file is incorrect'
if grep -Fq "$TOKEN" "$stdout_file" || grep -Fq "$TOKEN" "$stderr_file"; then
  fail 'tunnel token was exposed in step output'
fi

PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
DEVSPACE_PUBLIC_URL="$DEVSPACE_URL" \
ENABLE_DEVSPACE=true \
ENABLE_T3CODE=true \
T3_PUBLIC_URL="$T3_URL" \
  bash "$VERIFY_SCRIPT" >/dev/null

HOME="$MOCK_HOME" RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  bash "$CLEANUP_SCRIPT"
[[ ! -e "$token_file" ]] || fail 'cleanup retained the tunnel token file'

set +e
same_url_output="$(
  PATH="$MOCK_BIN:$PATH" \
  HOME="$MOCK_HOME" \
  RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  CLOUDFLARED_STARTUP_GRACE_SECONDS=0 \
  CLOUDFLARE_TUNNEL_TOKEN="$TOKEN" \
  DEVSPACE_PUBLIC_URL="$T3_URL" \
  ENABLE_DEVSPACE=true \
  ENABLE_T3CODE=true \
  T3_PUBLIC_URL="$T3_URL" \
    bash "$START_SCRIPT" 2>&1
)"
same_url_status=$?
set -e
[[ "$same_url_status" -eq 51 ]] || fail 'shared service hostname did not return E51'
[[ "$same_url_output" == 'E51' ]] || fail 'invalid tunnel config exposed unexpected output'

printf 'named tunnel tests passed\n'
