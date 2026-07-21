#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START_SCRIPT="$ROOT_DIR/scripts/start-quick-tunnels.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-public-services.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
TEMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TEMP_ROOT/bin"
MOCK_HOME="$TEMP_ROOT/home"
MOCK_RUNNER_TEMP="$TEMP_ROOT/runner-temp"
T3_URL='https://mock-t3.trycloudflare.com'
DEVSPACE_URL='https://mock-devspace.trycloudflare.com'

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

cat > "$MOCK_RUNNER_TEMP/private-runner-tools/cloudflared" <<MOCK
#!/usr/bin/env bash
set -euo pipefail
origin=''
while ((\$# > 0)); do
  if [[ "\$1" == '--url' ]]; then
    origin="\$2"
    shift 2
  else
    shift
  fi
done
case "\$origin" in
  http://127.0.0.1:3773) printf '%s\\n' '$T3_URL' ;;
  http://127.0.0.1:7676) printf '%s\\n' '$DEVSPACE_URL' ;;
  *) exit 1 ;;
esac
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
ENABLE_DEVSPACE=true \
ENABLE_T3CODE=true \
  bash "$START_SCRIPT" >"$stdout_file" 2>"$stderr_file"

diagnostic_dir="$MOCK_RUNNER_TEMP/private-runner-diagnostics"
t3_pid_file="$diagnostic_dir/cloudflared-t3code.pid"
devspace_pid_file="$diagnostic_dir/cloudflared-devspace.pid"
t3_url_file="$diagnostic_dir/t3code-public-url"
devspace_url_file="$diagnostic_dir/devspace-public-url"
for file in "$t3_pid_file" "$devspace_pid_file" "$t3_url_file" "$devspace_url_file"; do
  [[ -f "$file" ]] || fail "Quick Tunnel state file was not created: $file"
done
[[ "$(stat -c '%a' "$t3_url_file")" == '600' ]] || \
  fail 'T3 Quick Tunnel URL file permissions are not private'
[[ "$(stat -c '%a' "$devspace_url_file")" == '600' ]] || \
  fail 'DevSpace Quick Tunnel URL file permissions are not private'
[[ "$(cat "$t3_url_file")" == "$T3_URL" ]] || fail 'T3 Quick Tunnel URL is incorrect'
[[ "$(cat "$devspace_url_file")" == "$DEVSPACE_URL" ]] || \
  fail 'DevSpace Quick Tunnel URL is incorrect'
[[ "$(cat "$t3_url_file")" != "$(cat "$devspace_url_file")" ]] || \
  fail 'services unexpectedly share one Quick Tunnel URL'
if grep -Fq 'trycloudflare.com' "$stdout_file" || grep -Fq 'trycloudflare.com' "$stderr_file"; then
  fail 'Quick Tunnel URLs were exposed in step output'
fi

PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
ENABLE_DEVSPACE=true \
ENABLE_T3CODE=true \
  bash "$VERIFY_SCRIPT" >/dev/null

HOME="$MOCK_HOME" RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  bash "$CLEANUP_SCRIPT"
[[ ! -e "$t3_url_file" ]] || fail 'cleanup retained the T3 Quick Tunnel URL file'
[[ ! -e "$devspace_url_file" ]] || fail 'cleanup retained the DevSpace Quick Tunnel URL file'

set +e
invalid_output="$(
  PATH="$MOCK_BIN:$PATH" \
  HOME="$MOCK_HOME" \
  RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  ENABLE_DEVSPACE=false \
  ENABLE_T3CODE=false \
    bash "$START_SCRIPT" 2>&1
)"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 51 ]] || fail 'empty Quick Tunnel request did not return E51'
[[ "$invalid_output" == 'E51' ]] || fail 'invalid Quick Tunnel request exposed unexpected output'

printf 'quick tunnel tests passed\n'
