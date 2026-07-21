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

write_diagnostic() {
  local stage="$1"
  shift
  {
    printf 'stage=%s\n' "$stage"
    printf '%s\n' "$@"
  } > "$DIAGNOSTIC_OUTPUT"
}

export RUNNER_TEMP="$TEMP_ROOT"
rm -f "$DIAGNOSTIC_OUTPUT"

if ! bash "$INSTALL_SCRIPT"; then
  : > "$DIAGNOSTIC_OUTPUT"
  printf '%s\n' 'stage=install' >> "$DIAGNOSTIC_OUTPUT"
  if [[ -r "$LOG_FILE" ]]; then
    grep -E '(^|[[:space:]])(npm (error|ERR!)|gyp (error|ERR!)|error:|fatal:|CMake Error|make: \*\*\*)' \
      "$LOG_FILE" | tail -n 200 >> "$DIAGNOSTIC_OUTPUT" || true
  fi
  if [[ "$(wc -l < "$DIAGNOSTIC_OUTPUT")" -eq 1 ]]; then
    printf '%s\n' 'No allowlisted npm/node-gyp diagnostic line was captured.' >> "$DIAGNOSTIC_OUTPUT"
  fi
  exit 1
fi

t3_bin="$(command -v t3 || true)"
if [[ -z "$t3_bin" || ! -x "$t3_bin" ]]; then
  write_diagnostic binary 'The installed t3 executable was not found on PATH.'
  exit 1
fi

if ! version_output="$($t3_bin --version 2>&1)"; then
  write_diagnostic version-command 't3 --version exited nonzero.'
  exit 1
fi
if ! grep -Fq '0.0.28' <<< "$version_output"; then
  sanitized_version="$(tr -cd '[:alnum:]. _-\n' <<< "$version_output" | head -n 5)"
  write_diagnostic version-format "output=$sanitized_version"
  exit 1
fi

help_output="$TEMP_ROOT/t3-help.log"
if ! timeout 20 "$t3_bin" --help > "$help_output" 2>&1; then
  sanitized_help="$(tr -cd '[:alnum:].,:;/ _-\n' < "$help_output" | head -n 20)"
  write_diagnostic help "output=$sanitized_help"
  exit 1
fi

printf 'real T3 installation integration test passed\n'
