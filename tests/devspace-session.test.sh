#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREPARE_SCRIPT="$ROOT_DIR/scripts/prepare-target-workspace.sh"
START_SCRIPT="$ROOT_DIR/scripts/start-devspace.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
TEMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TEMP_ROOT/bin"
MOCK_HOME="$TEMP_ROOT/home"
MOCK_RUNNER_TEMP="$TEMP_ROOT/runner-temp"
TOKEN='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
PUBLIC_URL='https://mcp-repo-07.example.com'

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

mkdir -p "$MOCK_BIN" "$MOCK_HOME" "$MOCK_RUNNER_TEMP"

cat > "$MOCK_BIN/npm" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$MOCK_BIN/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == 'clone' ]]; then
  mkdir -p "${@: -1}/.git"
fi
MOCK

cat > "$MOCK_BIN/openssl" <<MOCK
#!/usr/bin/env bash
printf '%s\\n' '$TOKEN'
MOCK

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$MOCK_BIN/devspace" <<'MOCK'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do sleep 10; done
MOCK

chmod 0755 "$MOCK_BIN"/*

PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
TARGET_REPO='owner/repository' \
  bash "$PREPARE_SCRIPT" >/dev/null

stdout_file="$TEMP_ROOT/stdout"
stderr_file="$TEMP_ROOT/stderr"
PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
DEVSPACE_PUBLIC_URL="$PUBLIC_URL" \
  bash "$START_SCRIPT" >"$stdout_file" 2>"$stderr_file"

connection_dir="$MOCK_HOME/private-runner-session/devspace"
connection_file="$connection_dir/connection.txt"
[[ -f "$connection_file" ]] || fail 'connection file was not created'
[[ "$(stat -c '%a' "$connection_file")" == '600' ]] || \
  fail 'connection file permissions are not private'
grep -Fxq "MCP_URL=$PUBLIC_URL/mcp" "$connection_file" || \
  fail 'connection file does not contain the fixed MCP URL'
grep -Fxq "OWNER_TOKEN=$TOKEN" "$connection_file" || \
  fail 'connection file does not contain the owner token'

if grep -Fq "$PUBLIC_URL" "$stdout_file" || grep -Fq "$TOKEN" "$stdout_file"; then
  fail 'public step output exposes DevSpace connection material'
fi
grep -Fq '~/private-runner-session/devspace/connection.txt' "$stdout_file" || \
  fail 'success output does not identify the private connection file'
[[ ! -s "$stderr_file" ]] || fail 'successful startup wrote unexpected stderr'

HOME="$MOCK_HOME" RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  bash "$CLEANUP_SCRIPT"
[[ ! -e "$connection_dir" ]] || fail 'cleanup retained DevSpace connection material'

set +e
invalid_output="$(
  PATH="$MOCK_BIN:$PATH" \
  HOME="$MOCK_HOME" \
  RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  TARGET_REPO='' \
    bash "$PREPARE_SCRIPT" 2>&1
)"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 53 ]] || fail 'missing target did not return E53'
[[ "$invalid_output" == 'E53' ]] || fail 'missing target exposed unexpected output'

printf 'devspace session tests passed\n'
