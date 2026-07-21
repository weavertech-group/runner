#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREPARE_SCRIPT="$ROOT_DIR/scripts/prepare-target-workspace.sh"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-t3code.sh"
START_SCRIPT="$ROOT_DIR/scripts/start-t3code.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
TEMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TEMP_ROOT/bin"
MOCK_NODE_ROOT="$TEMP_ROOT/node"
MOCK_HOME="$TEMP_ROOT/home"
MOCK_RUNNER_TEMP="$TEMP_ROOT/runner-temp"
NPM_ENV_FILE="$TEMP_ROOT/npm-env"
NPM_ARGS_FILE="$TEMP_ROOT/npm-args"
PUBLIC_URL='https://mock-t3.trycloudflare.com'
PAIRING_TOKEN='pairing-token-123'

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

mkdir -p "$MOCK_BIN" "$MOCK_NODE_ROOT/bin" "$MOCK_NODE_ROOT/include/node" \
  "$MOCK_HOME" "$MOCK_RUNNER_TEMP/private-runner-diagnostics"
printf 'mock node header\n' > "$MOCK_NODE_ROOT/include/node/node.h"
printf '{}\n' > "$MOCK_NODE_ROOT/include/node/common.gypi"
printf '%s\n' "$PUBLIC_URL" \
  > "$MOCK_RUNNER_TEMP/private-runner-diagnostics/t3code-public-url"
chmod 0600 "$MOCK_RUNNER_TEMP/private-runner-diagnostics/t3code-public-url"

cat > "$MOCK_NODE_ROOT/bin/node" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
ln -s "$MOCK_NODE_ROOT/bin/node" "$MOCK_BIN/node"

cat > "$MOCK_BIN/npm" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'nodedir=%s\n' "${npm_config_nodedir-}"
  printf 'python=%s\n' "${npm_config_python-}"
} > "${NPM_ENV_FILE:?}"
printf '%s\n' "$@" > "${NPM_ARGS_FILE:?}"
exit 0
MOCK

cat > "$MOCK_BIN/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == 'clone' ]]; then
  mkdir -p "${@: -1}/.git"
fi
MOCK

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$MOCK_BIN/t3" <<MOCK
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1-}" == '--version' ]]; then
  printf '0.0.28\\n'
  exit 0
fi
if [[ "\${1-}" == 'project' && "\${2-}" == 'add' ]]; then
  exit 0
fi
if [[ "\${1-}" == 'serve' ]]; then
  printf 'T3 Code server is ready.\\n'
  printf 'Connection string: http://127.0.0.1:3773\\n'
  printf 'Token: $PAIRING_TOKEN\\n'
  trap 'exit 0' TERM INT
  while :; do sleep 10; done
fi
exit 1
MOCK

chmod 0755 "$MOCK_BIN"/* "$MOCK_NODE_ROOT/bin/node"

PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
TARGET_REPO='owner/repository' \
  bash "$PREPARE_SCRIPT" >/dev/null

PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
NPM_ENV_FILE="$NPM_ENV_FILE" \
NPM_ARGS_FILE="$NPM_ARGS_FILE" \
  bash "$INSTALL_SCRIPT"

grep -Fxq "nodedir=$MOCK_NODE_ROOT" "$NPM_ENV_FILE" || \
  fail 'T3 installer did not use the active local Node header root'
grep -Fxq 'python=/usr/bin/python3' "$NPM_ENV_FILE" || \
  fail 'T3 installer did not use the stable system Python'
grep -Fxq 'install' "$NPM_ARGS_FILE" || fail 'T3 npm install command is missing'
grep -Fxq 't3@0.0.28' "$NPM_ARGS_FILE" || fail 'T3 package pin changed'

stdout_file="$TEMP_ROOT/stdout"
stderr_file="$TEMP_ROOT/stderr"
PATH="$MOCK_BIN:$PATH" \
HOME="$MOCK_HOME" \
RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  bash "$START_SCRIPT" >"$stdout_file" 2>"$stderr_file"

connection_dir="$MOCK_HOME/private-runner-session/t3code"
connection_file="$connection_dir/connection.txt"
[[ -f "$connection_file" ]] || fail 'T3 connection file was not created'
[[ "$(stat -c '%a' "$connection_file")" == '600' ]] || \
  fail 'T3 connection file permissions are not private'
grep -Fxq "T3_URL=$PUBLIC_URL" "$connection_file" || \
  fail 'T3 connection file does not contain the Quick Tunnel URL'
grep -Fxq "PAIRING_URL=$PUBLIC_URL/pair#token=$PAIRING_TOKEN" "$connection_file" || \
  fail 'T3 connection file does not contain the pairing URL'

if grep -Fq "$PUBLIC_URL" "$stdout_file" || grep -Fq "$PAIRING_TOKEN" "$stdout_file"; then
  fail 'public step output exposes T3 connection material'
fi
grep -Fq '~/private-runner-session/t3code/connection.txt' "$stdout_file" || \
  fail 'T3 success output does not identify the private connection file'
[[ ! -s "$stderr_file" ]] || fail 'successful T3 startup wrote unexpected stderr'

HOME="$MOCK_HOME" RUNNER_TEMP="$MOCK_RUNNER_TEMP" \
  bash "$CLEANUP_SCRIPT"
[[ ! -e "$connection_dir" ]] || fail 'cleanup retained T3 connection material'
[[ ! -e "$MOCK_RUNNER_TEMP/t3code-home" ]] || fail 'cleanup retained T3 state'

printf 't3code session tests passed\n'
