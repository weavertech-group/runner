#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
tunnel_token="${CLOUDFLARE_TUNNEL_TOKEN-}"
enable_devspace="${ENABLE_DEVSPACE-false}"
enable_t3code="${ENABLE_T3CODE-false}"
devspace_public_url="${DEVSPACE_PUBLIC_URL-}"
t3_public_url="${T3_PUBLIC_URL-}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
tool_dir="$runner_temp/private-runner-tools"
cloudflared_bin="$tool_dir/cloudflared"
cloudflared_log="$diagnostic_dir/cloudflared.log"
cloudflared_pid_file="$diagnostic_dir/cloudflared.pid"
token_file="$diagnostic_dir/cloudflared-token"
startup_grace_seconds="${CLOUDFLARED_STARTUP_GRACE_SECONDS:-10}"

fail() {
  printf 'E51\n' >&2
  exit 51
}

is_https_origin() {
  [[ "$1" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]]
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail
[[ -x "$cloudflared_bin" ]] || fail
command -v setsid >/dev/null 2>&1 || fail
[[ -n "$tunnel_token" ]] || fail
[[ "$enable_devspace" == true || "$enable_t3code" == true ]] || fail
[[ "$startup_grace_seconds" =~ ^[0-9]+$ && "$startup_grace_seconds" -le 30 ]] || fail

if [[ "$enable_devspace" == true ]]; then
  is_https_origin "$devspace_public_url" || fail
fi
if [[ "$enable_t3code" == true ]]; then
  is_https_origin "$t3_public_url" || fail
fi
if [[ "$enable_devspace" == true && "$enable_t3code" == true && \
      "${devspace_public_url%/}" == "${t3_public_url%/}" ]]; then
  fail
fi

printf '%s' "$tunnel_token" > "$token_file" || fail
chmod 0600 "$token_file" || fail
unset CLOUDFLARE_TUNNEL_TOKEN tunnel_token
: > "$cloudflared_log" || fail
chmod 0600 "$cloudflared_log" || fail

setsid "$cloudflared_bin" tunnel --no-autoupdate --protocol http2 \
  run --token-file "$token_file" \
  > "$cloudflared_log" 2>&1 &
cloudflared_pid=$!
printf '%s\n' "$cloudflared_pid" > "$cloudflared_pid_file"

sleep "$startup_grace_seconds"
kill -0 "$cloudflared_pid" 2>/dev/null || fail

printf '%s\n' 'Named Cloudflare Tunnel connector started.'
