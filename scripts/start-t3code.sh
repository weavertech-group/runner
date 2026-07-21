#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
workspace="$runner_temp/target-workspace"
t3_home="$runner_temp/t3code-home"
connection_dir="${HOME:?HOME is required}/private-runner-session/t3code"
public_url_file="$diagnostic_dir/t3code-public-url"
setup_log="$diagnostic_dir/t3code-setup.log"
t3_log="$diagnostic_dir/t3code.log"
t3_pid_file="$diagnostic_dir/t3code.pid"

fail() {
  printf 'E62\n' >&2
  exit 62
}

umask 077
install -d -m 0700 "$diagnostic_dir" "$connection_dir" "$t3_home" || fail
: > "$setup_log" || fail
: > "$t3_log" || fail
chmod 0600 "$setup_log" "$t3_log" || fail
command -v setsid >/dev/null 2>&1 || fail
t3_bin="$(command -v t3 || true)"
[[ -n "$t3_bin" && -x "$t3_bin" ]] || fail
[[ -d "$workspace/.git" ]] || fail
[[ -r "$public_url_file" ]] || fail
public_url="$(<"$public_url_file")"
[[ "$public_url" =~ ^https://[-a-z0-9]+[.]trycloudflare[.]com$ ]] || fail

if ! timeout 120 "$t3_bin" project add \
  --base-dir "$t3_home" \
  "$workspace" \
  >> "$setup_log" 2>&1; then
  fail
fi

setsid env T3CODE_HOME="$t3_home" \
  "$t3_bin" serve \
  --base-dir "$t3_home" \
  --host 127.0.0.1 \
  --port 3773 \
  "$workspace" \
  > "$t3_log" 2>&1 &
t3_pid=$!
printf '%s\n' "$t3_pid" > "$t3_pid_file"

pairing_token=''
local_ready=false
for _ in $(seq 1 90); do
  if ! kill -0 "$t3_pid" 2>/dev/null; then
    fail
  fi
  pairing_token="$(sed -n 's/^Token: //p' "$t3_log" | head -n 1 | tr -d '\r' || true)"
  if [[ -n "$pairing_token" ]] && \
     curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
       http://127.0.0.1:3773/ >/dev/null 2>> "$t3_log"; then
    local_ready=true
    break
  fi
  sleep 1
done
[[ "$local_ready" == true && -n "$pairing_token" ]] || fail

pairing_url="$public_url/pair#token=$pairing_token"
printf '%s\n' "$public_url" > "$connection_dir/t3-url"
printf '%s\n' "$pairing_url" > "$connection_dir/pairing-url"
printf 'T3_URL=%s\nPAIRING_URL=%s\n' "$public_url" "$pairing_url" \
  > "$connection_dir/connection.txt"
chmod 0600 "$connection_dir/t3-url" \
  "$connection_dir/pairing-url" "$connection_dir/connection.txt"

printf '%s\n' 'T3 Code ready; read ~/private-runner-session/t3code/connection.txt over private SSH.'
