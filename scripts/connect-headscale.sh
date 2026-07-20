#!/usr/bin/env bash

set -euo pipefail

diagnostic_dir="${RUNNER_TEMP:?RUNNER_TEMP is required}/private-runner-diagnostics"
status_file="$diagnostic_dir/tailscale-status.json"
connect_log="$diagnostic_dir/connect.log"
daemon_log="$diagnostic_dir/tailscaled.log"
public_key="${SSH_PUBLIC_KEY-}"

mkdir -p "$diagnostic_dir"
chmod 700 "$diagnostic_dir"

if [[ -z "${HEADSCALE_AUTHKEY-}" ]]; then
  printf 'E22\n' >&2
  exit 22
fi
if [[ -z "${HEADSCALE_URL-}" ]]; then
  printf 'E21\n' >&2
  exit 21
fi

printf '::add-mask::%s\n' "$HEADSCALE_AUTHKEY"

if ! sudo tailscaled \
  --state=mem: \
  --socket=/var/run/tailscale/tailscaled.sock \
  >"$daemon_log" 2>&1 & then
  printf 'E21\n' >&2
  exit 21
fi
echo "$!" > "$diagnostic_dir/tailscaled.pid"

ready=false
for _ in {1..40}; do
  if sudo tailscale status >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.5
done
[[ "$ready" == true ]] || {
  printf 'E21\n' >&2
  exit 21
}

node_name="gha-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
up_args=(
  --login-server="$HEADSCALE_URL"
  --auth-key="$HEADSCALE_AUTHKEY"
  --hostname="$node_name"
  --accept-dns=true
  --timeout=2m
)

if [[ -z "$public_key" ]]; then
  up_args+=(--ssh)
fi

if ! sudo tailscale up "${up_args[@]}" >"$connect_log" 2>&1; then
  if grep -Eiq \
    '((auth|preauth).*(key|token).*(invalid|expired|unauthorized|not found)|(invalid|expired|unauthorized|not found).*(auth|preauth).*(key|token))' \
    "$connect_log"; then
    printf 'E22\n' >&2
    exit 22
  fi
  printf 'E21\n' >&2
  exit 21
fi

if ! sudo tailscale status --json >"$status_file" 2>>"$connect_log"; then
  printf 'E23\n' >&2
  exit 23
fi

fqdn="$(jq -er '.Self.DNSName | strings | select(length > 1) | rtrimstr(".")' "$status_file" 2>/dev/null)" || {
  printf 'E23\n' >&2
  exit 23
}

if [[ -n "${HEADSCALE_MAGIC_DNS_DOMAIN-}" && "$fqdn" != *".${HEADSCALE_MAGIC_DNS_DOMAIN}" ]]; then
  printf 'E23\n' >&2
  exit 23
fi

printf '%s\n' "$fqdn" > "$diagnostic_dir/runner-fqdn"
chmod 600 "$diagnostic_dir/runner-fqdn" "$status_file"

if [[ -z "$public_key" ]]; then
  if ! sudo tailscale set --ssh=true >>"$connect_log" 2>&1; then
    printf 'E24\n' >&2
    exit 24
  fi
else
  bash "$(dirname "$0")/session-lib.sh" validate-key "$public_key"
  install -d -m 700 "$HOME/.ssh"
  printf '%s\n' "$public_key" >> "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"

  printf '%s\n' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PermitRootLogin no' \
    'AllowUsers runner' | \
    sudo tee /etc/ssh/sshd_config.d/99-private-runner.conf >/dev/null

  if ! sudo systemctl restart ssh >"$diagnostic_dir/sshd.log" 2>&1; then
    printf 'E24\n' >&2
    exit 24
  fi
fi
