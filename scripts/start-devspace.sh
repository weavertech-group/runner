#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
target_repo="${TARGET_REPO-}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
tool_dir="$runner_temp/private-runner-tools"
workspace="$runner_temp/devspace-workspace"
state_dir="$runner_temp/devspace-state"
worktree_dir="$runner_temp/devspace-worktrees"
config_dir="$runner_temp/devspace-config"
connection_dir="${HOME:?HOME is required}/private-runner-session/devspace"
setup_log="$diagnostic_dir/devspace-setup.log"
cloudflared_log="$diagnostic_dir/cloudflared.log"
devspace_log="$diagnostic_dir/devspace.log"
cloudflared_pid_file="$diagnostic_dir/cloudflared.pid"
devspace_pid_file="$diagnostic_dir/devspace.pid"
cloudflared_bin="$tool_dir/cloudflared"
devspace_package='@waishnav/devspace@1.0.4'

fail() {
  local code="$1"
  printf 'E%s\n' "$code" >&2
  exit "$code"
}

umask 077
install -d -m 0700 "$diagnostic_dir" "$connection_dir" || fail 52
: > "$setup_log" || fail 52
chmod 0600 "$setup_log" || fail 52

if [[ -z "$target_repo" || \
      ! "$target_repo" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9._-]{1,100}$ ]]; then
  fail 50
fi
[[ -x "$cloudflared_bin" ]] || fail 51
command -v setsid >/dev/null 2>&1 || fail 52

if ! timeout 300 npm install --global --no-audit --no-fund "$devspace_package" \
  >> "$setup_log" 2>&1; then
  fail 52
fi
devspace_bin="$(command -v devspace || true)"
[[ -n "$devspace_bin" && -x "$devspace_bin" ]] || fail 52

rm -rf "$workspace" "$state_dir" "$worktree_dir" "$config_dir"
if ! GIT_TERMINAL_PROMPT=0 timeout 600 git clone --quiet \
  "https://github.com/${target_repo}.git" "$workspace" \
  >> "$setup_log" 2>&1; then
  fail 53
fi

unset TARGET_REPO TARGET_REPO_AUTH GITHUB_TOKEN HEADSCALE_AUTHKEY HEADSCALE_URL

owner_token="$(openssl rand -hex 32)" || fail 52
: > "$cloudflared_log" || fail 51
chmod 0600 "$cloudflared_log" || fail 51
setsid "$cloudflared_bin" tunnel --no-autoupdate --protocol http2 \
  --url http://127.0.0.1:7676 \
  > "$cloudflared_log" 2>&1 &
cloudflared_pid=$!
printf '%s\n' "$cloudflared_pid" > "$cloudflared_pid_file"

public_url=''
for _ in $(seq 1 60); do
  if ! kill -0 "$cloudflared_pid" 2>/dev/null; then
    fail 51
  fi
  public_url="$(grep -oE 'https://[-a-z0-9]+[.]trycloudflare[.]com' \
    "$cloudflared_log" | head -n 1 || true)"
  [[ -n "$public_url" ]] && break
  sleep 1
done
[[ -n "$public_url" ]] || fail 51

: > "$devspace_log" || fail 52
chmod 0600 "$devspace_log" || fail 52
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
    fail 52
  fi
  if curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    http://127.0.0.1:7676/.well-known/oauth-authorization-server \
    >/dev/null 2>> "$devspace_log"; then
    local_ready=true
    break
  fi
  sleep 1
done
[[ "$local_ready" == true ]] || fail 52

public_ready=false
for _ in $(seq 1 60); do
  if curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    "$public_url/.well-known/oauth-protected-resource/mcp" \
    >/dev/null 2>> "$devspace_log"; then
    public_ready=true
    break
  fi
  sleep 1
done
[[ "$public_ready" == true ]] || fail 54

mcp_url="$public_url/mcp"
printf '%s\n' "$mcp_url" > "$connection_dir/mcp-url"
printf '%s\n' "$owner_token" > "$connection_dir/owner-token"
printf 'MCP_URL=%s\nOWNER_TOKEN=%s\n' "$mcp_url" "$owner_token" \
  > "$connection_dir/connection.txt"
chmod 0600 "$connection_dir/mcp-url" \
  "$connection_dir/owner-token" "$connection_dir/connection.txt"

printf '%s\n' 'DevSpace ready; read ~/private-runner-session/devspace/connection.txt over private SSH.'
