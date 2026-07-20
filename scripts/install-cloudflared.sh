#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
tool_dir="$runner_temp/private-runner-tools"
log_file="$diagnostic_dir/cloudflared-install.log"
version='2026.7.2'
sha256='ec905ea7b7e327ff8abdde8cb64697a2152de74dbcdbf6aec9db8364eb3886cd'
asset='cloudflared-linux-amd64'
url="https://github.com/cloudflare/cloudflared/releases/download/${version}/${asset}"
binary="$tool_dir/cloudflared"
temporary="$tool_dir/.cloudflared.download"

fail() {
  printf 'E51\n' >&2
  exit 51
}

install -d -m 0700 "$diagnostic_dir" "$tool_dir" || fail
: > "$log_file" || fail
chmod 0600 "$log_file" || fail

[[ "$(uname -s)" == 'Linux' && "$(uname -m)" == 'x86_64' ]] || fail

rm -f "$temporary"
if ! curl --fail --silent --show-error --location --retry 3 \
  --proto '=https' --tlsv1.2 --output "$temporary" "$url" \
  2>> "$log_file"; then
  fail
fi

if ! printf '%s  %s\n' "$sha256" "$temporary" | sha256sum --check --status \
  2>> "$log_file"; then
  fail
fi

chmod 0755 "$temporary" || fail
mv -f "$temporary" "$binary" || fail
"$binary" --version >> "$log_file" 2>&1 || fail
