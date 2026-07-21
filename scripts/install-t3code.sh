#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
log_file="$diagnostic_dir/t3code-install.log"
t3_package='t3@0.0.28'

fail() {
  printf 'E61\n' >&2
  exit 61
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail
: > "$log_file" || fail
chmod 0600 "$log_file" || fail

if ! timeout 300 npm install --global --no-audit --no-fund "$t3_package" \
  >> "$log_file" 2>&1; then
  fail
fi

t3_bin="$(command -v t3 || true)"
[[ -n "$t3_bin" && -x "$t3_bin" ]] || fail
"$t3_bin" --version >> "$log_file" 2>&1 || fail
