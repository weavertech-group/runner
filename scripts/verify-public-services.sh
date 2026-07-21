#!/usr/bin/env bash

set -euo pipefail

enable_devspace="${ENABLE_DEVSPACE-false}"
enable_t3code="${ENABLE_T3CODE-false}"
runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
verify_log="$diagnostic_dir/public-services.log"

fail() {
  local code="$1"
  printf 'E%s\n' "$code" >&2
  exit "$code"
}

read_quick_tunnel_url() {
  local file="$1"
  local value=''
  [[ -r "$file" ]] || return 1
  value="$(<"$file")"
  [[ "$value" =~ ^https://[-a-z0-9]+[.]trycloudflare[.]com$ ]] || return 1
  printf '%s\n' "$value"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 60); do
    if curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
      "$url" >/dev/null 2>> "$verify_log"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

verify_websocket() {
  local url="$1"
  node - "$url" >> "$verify_log" 2>&1 <<'NODE'
const input = new URL(process.argv[2]);
input.protocol = input.protocol === "https:" ? "wss:" : "ws:";
const socket = new WebSocket(input);
const timer = setTimeout(() => {
  socket.close();
  process.exit(1);
}, 10000);
socket.addEventListener("open", () => {
  clearTimeout(timer);
  socket.close();
  process.exit(0);
});
socket.addEventListener("error", () => {
  clearTimeout(timer);
  process.exit(1);
});
NODE
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail 51
: > "$verify_log" || fail 51
chmod 0600 "$verify_log" || fail 51

if [[ "$enable_devspace" == true ]]; then
  devspace_public_url="$(read_quick_tunnel_url "$diagnostic_dir/devspace-public-url")" || fail 54
  wait_for_http "$devspace_public_url/.well-known/oauth-protected-resource/mcp" || fail 54
fi

if [[ "$enable_t3code" == true ]]; then
  t3_public_url="$(read_quick_tunnel_url "$diagnostic_dir/t3code-public-url")" || fail 63
  wait_for_http "$t3_public_url/" || fail 63
  verify_websocket "$t3_public_url/" || fail 63
fi

printf '%s\n' 'Public optional services are ready.'
