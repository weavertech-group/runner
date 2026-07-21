#!/usr/bin/env bash

set -u

runner_temp="${RUNNER_TEMP:-/tmp}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
connection_root="${HOME:-/home/runner}/private-runner-session"

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

stop_process_group "$diagnostic_dir/cloudflared.pid"
stop_process_group "$diagnostic_dir/t3code.pid"
stop_process_group "$diagnostic_dir/devspace.pid"
rm -f "$diagnostic_dir/cloudflared-token"
rm -rf "$connection_root/devspace" "$connection_root/t3code"
rm -rf \
  "$runner_temp/target-workspace" \
  "$runner_temp/devspace-state" \
  "$runner_temp/devspace-worktrees" \
  "$runner_temp/devspace-config" \
  "$runner_temp/t3code-home"

if command -v tailscale >/dev/null 2>&1; then
  sudo tailscale logout >/dev/null 2>&1 || true
fi

if [[ -r "$diagnostic_dir/tailscaled.pid" ]]; then
  daemon_pid="$(<"$diagnostic_dir/tailscaled.pid")"
  if [[ "$daemon_pid" =~ ^[0-9]+$ ]]; then
    sudo kill "$daemon_pid" >/dev/null 2>&1 || true
  fi
fi

rm -f "$runner_temp/target-repo-credential"
git config --global --unset-all credential.helper >/dev/null 2>&1 || true
git config --global --unset-all credential.https://github.com.useHttpPath >/dev/null 2>&1 || true
