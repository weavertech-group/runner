#!/usr/bin/env bash

set -u

diagnostic_dir="${RUNNER_TEMP:-/tmp}/private-runner-diagnostics"

if command -v tailscale >/dev/null 2>&1; then
  sudo tailscale logout >/dev/null 2>&1 || true
fi

if [[ -r "$diagnostic_dir/tailscaled.pid" ]]; then
  daemon_pid="$(<"$diagnostic_dir/tailscaled.pid")"
  if [[ "$daemon_pid" =~ ^[0-9]+$ ]]; then
    sudo kill "$daemon_pid" >/dev/null 2>&1 || true
  fi
fi

rm -f "${RUNNER_TEMP:-/tmp}/target-repo-credential"
git config --global --unset-all credential.helper >/dev/null 2>&1 || true
git config --global --unset-all credential.https://github.com.useHttpPath >/dev/null 2>&1 || true
