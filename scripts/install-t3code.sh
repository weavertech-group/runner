#!/usr/bin/env bash

set -euo pipefail

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
log_file="$diagnostic_dir/t3code-install.log"
t3_package='t3@0.0.28'

fail() {
  local stage="${1:-unknown}"
  printf 'E61:%s\n' "$stage" >&2
  exit 61
}

umask 077
install -d -m 0700 "$diagnostic_dir" || fail setup
: > "$log_file" || fail setup
chmod 0600 "$log_file" || fail setup

node_executable="$(command -v node || true)"
[[ -n "$node_executable" && -x "$node_executable" ]] || fail node
node_executable="$(readlink -f "$node_executable")" || fail node
node_root="$(dirname "$(dirname "$node_executable")")"
[[ -r "$node_root/include/node/node.h" ]] || fail headers
[[ -r "$node_root/include/node/common.gypi" ]] || fail headers

# The development setup installs a newer mise-managed Python and prepends its
# shims for operator use. Native npm builds should instead use Ubuntu's stable
# system Python together with the headers from the active setup-node runtime.
python_executable='/usr/bin/python3'
[[ -x "$python_executable" ]] || fail python

# t3 depends on node-pty. When no matching prebuild is available, node-gyp
# otherwise downloads headers even though setup-node already installed matching
# headers locally. Pin both build inputs so the installation is independent from
# external header downloads and from the operator-facing mise Python version.
if ! npm_config_nodedir="$node_root" \
    npm_config_python="$python_executable" \
    timeout 300 npm install --global --no-audit --no-fund "$t3_package" \
    >> "$log_file" 2>&1; then
  fail npm
fi

t3_bin="$(command -v t3 || true)"
[[ -n "$t3_bin" && -x "$t3_bin" ]] || fail binary
"$t3_bin" --version >> "$log_file" 2>&1 || fail version
