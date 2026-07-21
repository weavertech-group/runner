#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-t3code.sh"
TEMP_ROOT="$(mktemp -d)"
LOG_FILE="$TEMP_ROOT/private-runner-diagnostics/t3code-install.log"
DIAGNOSTIC_OUTPUT="${T3_INSTALL_DIAGNOSTIC_OUTPUT:?T3_INSTALL_DIAGNOSTIC_OUTPUT is required}"

cleanup() {
  npm uninstall --global t3 >/dev/null 2>&1 || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

export RUNNER_TEMP="$TEMP_ROOT"
rm -f "$DIAGNOSTIC_OUTPUT"

if ! bash "$INSTALL_SCRIPT"; then
  : > "$DIAGNOSTIC_OUTPUT"
  if [[ -r "$LOG_FILE" ]]; then
    grep -E '(^|[[:space:]])(npm (error|ERR!)|gyp (error|ERR!)|error:|fatal:|CMake Error|make: \*\*\*)' \
      "$LOG_FILE" | tail -n 200 > "$DIAGNOSTIC_OUTPUT" || true
  fi
  if [[ ! -s "$DIAGNOSTIC_OUTPUT" ]]; then
    printf '%s\n' 'No allowlisted npm/node-gyp diagnostic line was captured.' > "$DIAGNOSTIC_OUTPUT"
  fi
  exit 1
fi

t3_bin="$(command -v t3 || true)"
[[ -n "$t3_bin" && -x "$t3_bin" ]]
version="$($t3_bin --version | tail -n 1)"
[[ "$version" == '0.0.28' ]]
timeout 20 "$t3_bin" --help >/dev/null

printf 'real T3 installation integration test passed\n'
