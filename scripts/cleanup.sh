#!/usr/bin/env bash

set -u

diagnostic_dir="${RUNNER_TEMP:-/tmp}/private-runner-diagnostics"
connection_dir="${HOME:-/home/runner}/private-runner-session/devspace"

stop_process_group() {
  local pid_file="$1"
  local pid=''

  [[ -r "$pid_file" ]] || return 0
  pid="$(<"$pid_file")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0

  kill -- "-$pid" >/dev/null 2>&1 || kill "$pid" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    kill -0 "$pid" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -KILL "$pid" >/dev/null 2>&1 || true
}

stop_process_group "$diagnostic_dir/devspace.pid"
stop_process_group "$diagnostic_dir/cloudflared.pid"
rm -rf "$connection_dir"

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
