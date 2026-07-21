#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
enable_devspace="${ENABLE_DEVSPACE-false}"
enable_t3code="${ENABLE_T3CODE-false}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
tool_dir="$runner_temp/private-runner-tools"
cloudflared_bin="$tool_dir/cloudflared"
url_pattern='https://[-a-z0-9]+[.]trycloudflare[.]com'

fail() {
  printf 'E51\n' >&2
  exit 51
}

start_quick_tunnel() {
  local service="$1"
  local origin="$2"
  local log_file="$diagnostic_dir/cloudflared-${service}.log"
  local pid_file="$diagnostic_dir/cloudflared-${service}.pid"
  local url_file="$diagnostic_dir/${service}-public-url"
  local pid=''
  local public_url=''

  : > "$log_file" || fail
  chmod 0600 "$log_file" || fail
  setsid "$cloudflared_bin" tunnel --no-autoupdate --protocol http2 \
    --url "$origin" \
    > "$log_file" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pid_file" || fail

  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || fail
    public_url="$(grep -oE "$url_pattern" "$log_file" | head -n 1 || true)"
    [[ -n "$public_url" ]] && break
    sleep 1
  done
  [[ "$public_url" =~ ^https://[-a-z0-9]+[.]trycloudflare[.]com$ ]] || fail
  printf '%s\n' "$public_url" > "$url_file" || fail
  chmod 0600 "$url_file" || fail
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail
[[ -x "$cloudflared_bin" ]] || fail
command -v setsid >/dev/null 2>&1 || fail
[[ "$enable_devspace" == true || "$enable_t3code" == true ]] || fail

if [[ "$enable_devspace" == true ]]; then
  start_quick_tunnel devspace http://127.0.0.1:7676
fi
if [[ "$enable_t3code" == true ]]; then
  start_quick_tunnel t3code http://127.0.0.1:3773
fi

printf '%s\n' 'Cloudflare Quick Tunnel endpoints are ready.'
