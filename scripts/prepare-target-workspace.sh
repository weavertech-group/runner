#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
target_repo="${TARGET_REPO-}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
workspace="$runner_temp/target-workspace"
setup_log="$diagnostic_dir/workspace-setup.log"

fail() {
  printf 'E53\n' >&2
  exit 53
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail
: > "$setup_log" || fail
chmod 0600 "$setup_log" || fail

if [[ -z "$target_repo" || \
      ! "$target_repo" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9._-]{1,100}$ ]]; then
  fail
fi

rm -rf "$workspace"
if ! GIT_TERMINAL_PROMPT=0 timeout 600 git clone --quiet \
  "https://github.com/${target_repo}.git" "$workspace" \
  >> "$setup_log" 2>&1; then
  fail
fi

[[ -d "$workspace/.git" ]] || fail
printf '%s\n' 'Target workspace ready.'
