#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
public_url="${DEVSPACE_PUBLIC_URL-}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
workspace="$runner_temp/target-workspace"
state_dir="$runner_temp/devspace-state"
worktree_dir="$runner_temp/devspace-worktrees"
config_dir="$runner_temp/devspace-config"
connection_dir="${HOME:?HOME is required}/private-runner-session/devspace"
setup_log="$diagnostic_dir/devspace-setup.log"
devspace_log="$diagnostic_dir/devspace.log"
devspace_pid_file="$diagnostic_dir/devspace.pid"
devspace_package='@waishnav/devspace@1.0.4'

fail() {
  printf 'E52\n' >&2
  exit 52
}

normalize_https_origin() {
  local value="$1"
  if [[ ! "$value" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]]; then
    return 1
  fi
  printf '%s\n' "${value%/}"
}

umask 077
install -d -m 0700 "$diagnostic_dir" "$connection_dir" || fail
: > "$setup_log" || fail
chmod 0600 "$setup_log" || fail
command -v setsid >/dev/null 2>&1 || fail
[[ -d "$workspace/.git" ]] || fail
public_url="$(normalize_https_origin "$public_url")" || fail

if ! timeout 300 npm install --global --no-audit --no-fund "$devspace_package" \
  >> "$setup_log" 2>&1; then
  fail
fi
devspace_bin="$(command -v devspace || true)"
[[ -n "$devspace_bin" && -x "$devspace_bin" ]] || fail

rm -rf "$state_dir" "$worktree_dir" "$config_dir"
owner_token="$(openssl rand -hex 32)" || fail
: > "$devspace_log" || fail
chmod 0600 "$devspace_log" || fail
setsid env \
  HOST=127.0.0.1 \
  PORT=7676 \
  DEVSPACE_CONFIG_DIR="$config_dir" \
  DEVSPACE_ALLOWED_ROOTS="$workspace" \
  DEVSPACE_PUBLIC_BASE_URL="$public_url" \
  DEVSPACE_OAUTH_OWNER_TOKEN="$owner_token" \
  DEVSPACE_STATE_DIR="$state_dir" \
  DEVSPACE_WORKTREE_ROOT="$worktree_dir" \
  DEVSPACE_TOOL_MODE=full \
  DEVSPACE_WIDGETS=changes \
  DEVSPACE_SUBAGENTS=0 \
  DEVSPACE_LOG_SHELL_COMMANDS=0 \
  "$devspace_bin" serve \
  > "$devspace_log" 2>&1 &
devspace_pid=$!
printf '%s\n' "$devspace_pid" > "$devspace_pid_file"

local_ready=false
for _ in $(seq 1 60); do
  if ! kill -0 "$devspace_pid" 2>/dev/null; then
    fail
  fi
  if curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    http://127.0.0.1:7676/.well-known/oauth-authorization-server \
    >/dev/null 2>> "$devspace_log"; then
    local_ready=true
    break
  fi
  sleep 1
done
[[ "$local_ready" == true ]] || fail

mcp_url="$public_url/mcp"
printf '%s\n' "$mcp_url" > "$connection_dir/mcp-url"
printf '%s\n' "$owner_token" > "$connection_dir/owner-token"
printf 'MCP_URL=%s\nOWNER_TOKEN=%s\n' "$mcp_url" "$owner_token" \
  > "$connection_dir/connection.txt"
chmod 0600 "$connection_dir/mcp-url" \
  "$connection_dir/owner-token" "$connection_dir/connection.txt"

printf '%s\n' 'DevSpace ready; read ~/private-runner-session/devspace/connection.txt over private SSH.'
