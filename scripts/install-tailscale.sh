#!/usr/bin/env bash

set -euo pipefail

readonly TAILSCALE_VERSION='1.94.2'
readonly TAILSCALE_ARCH='amd64'
readonly TAILSCALE_SHA256='c6f99a5d774c7783b56902188d69e9756fc3dddfb08ac6be4cb2585f3fecdc32'

diagnostic_dir="${RUNNER_TEMP:?RUNNER_TEMP is required}/private-runner-diagnostics"
archive="$diagnostic_dir/tailscale.tgz"
extract_dir="$diagnostic_dir/tailscale"
mkdir -p "$diagnostic_dir" "$extract_dir"
chmod 700 "$diagnostic_dir"

if ! {
  curl --fail --silent --show-error --location \
    --output "$archive" \
    "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TAILSCALE_ARCH}.tgz"
  printf '%s  %s\n' "$TAILSCALE_SHA256" "$archive" | sha256sum --check --status
  tar -xzf "$archive" --strip-components=1 -C "$extract_dir"
  sudo install -m 0755 "$extract_dir/tailscale" /usr/local/bin/tailscale
  sudo install -m 0755 "$extract_dir/tailscaled" /usr/local/bin/tailscaled
} >"$diagnostic_dir/install.log" 2>&1; then
  printf 'E20\n' >&2
  exit 20
fi
