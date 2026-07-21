#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-t3code.sh"
TEMP_ROOT="$(mktemp -d)"
LOG_FILE="$TEMP_ROOT/private-runner-diagnostics/t3code-install.log"

cleanup() {
  npm uninstall --global t3 >/dev/null 2>&1 || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

export RUNNER_TEMP="$TEMP_ROOT"

if ! bash "$INSTALL_SCRIPT"; then
  if [[ -r "$LOG_FILE" ]]; then
    printf '%s\n' 'Sanitized T3 installation diagnostics:' >&2
    grep -E '(^|[[:space:]])(npm (error|ERR!)|gyp (error|ERR!)|error:|fatal:|CMake Error|make: \*\*\*)' \
      "$LOG_FILE" | tail -n 160 >&2 || true
  fi
  exit 1
fi

t3_bin="$(command -v t3 || true)"
[[ -n "$t3_bin" && -x "$t3_bin" ]]
version="$($t3_bin --version | tail -n 1)"
[[ "$version" == '0.0.28' ]]
timeout 20 "$t3_bin" --help >/dev/null

printf 'real T3 installation integration test passed\n'
