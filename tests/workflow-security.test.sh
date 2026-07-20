#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
CONNECT_SCRIPT="$ROOT_DIR/scripts/connect-headscale.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail 'workflow is missing'

if grep -Eq 'uses: [^@]+@(main|master|v[0-9]+([.]?[0-9]+)*)$' "$WORKFLOW"; then
  fail 'third-party actions must be pinned to a full commit SHA'
fi

if grep -Eq '(^|[[:space:]])(set -x|env|printenv)([[:space:]]|$)' "$WORKFLOW"; then
  fail 'workflow contains a command that can expose secrets'
fi

grep -Fq 'TARGET_REPO_AUTH: ${{ secrets.TARGET_REPO_AUTH }}' "$WORKFLOW" || \
  fail 'selected repository credential is not scoped explicitly'

grep -Fq "if: \${{ inputs.target_repo != '' }}" "$WORKFLOW" || \
  fail 'repository credential is referenced without an input guard'

grep -Fq 'pull_request_target' "$WORKFLOW" && \
  fail 'workflow must not use pull_request_target'

grep -Fq 'openssh-server' "$CONNECT_SCRIPT" || \
  fail 'fallback mode must install the SSH server explicitly'

grep -Fq 'ListenAddress %s' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must bind only to the Tailscale address'

printf 'workflow security tests passed\n'
