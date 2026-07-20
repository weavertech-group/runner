#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
CONNECT_SCRIPT="$ROOT_DIR/scripts/connect-headscale.sh"
ALLOWLIST="$ROOT_DIR/.github/target-repositories.txt"

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

grep -Fq "if: \${{ inputs.target_id != '' }}" "$WORKFLOW" || \
  fail 'repository credential is referenced without an input guard'

grep -Fq 'TARGET_REPO: ${{ secrets.TARGET_REPO }}' "$WORKFLOW" || \
  fail 'real repository identity must come from the selected Environment'

grep -Fq 'HEADSCALE_URL: ${{ secrets.HEADSCALE_URL }}' "$WORKFLOW" || \
  fail 'Headscale URL must be masked as sensitive metadata'

grep -Fq 'HEADSCALE_MAGIC_DNS_DOMAIN: ${{ secrets.HEADSCALE_MAGIC_DNS_DOMAIN }}' "$WORKFLOW" || \
  fail 'MagicDNS domain must be masked as sensitive metadata'

grep -Fq 'deployment: false' "$WORKFLOW" || \
  fail 'session jobs must not create public deployment records'

grep -Fq 'timeout-minutes: 360' "$WORKFLOW" || \
  fail 'session job must use the full GitHub-hosted six-hour limit'

grep -Fq 'run: sleep infinity' "$WORKFLOW" || \
  fail 'session must wait for platform termination instead of exiting early'

grep -Fq 'inputs.target_repo' "$WORKFLOW" && \
  fail 'real repository names must not come from public workflow inputs'

if sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$ALLOWLIST" | grep -Fq '/'; then
  fail 'public allowlist must not contain owner/repository names'
fi

grep -Fq 'pull_request_target' "$WORKFLOW" && \
  fail 'workflow must not use pull_request_target'

grep -Fq 'openssh-server' "$CONNECT_SCRIPT" || \
  fail 'fallback mode must install the SSH server explicitly'

grep -Fq 'ListenAddress %s' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must bind only to the Tailscale address'

grep -Fq '/health' "$CONNECT_SCRIPT" || \
  fail 'Headscale health must be checked before classifying registration errors'

grep -Fq 'sudo install -d -m 0755 /var/run/tailscale' "$CONNECT_SCRIPT" || \
  fail 'direct tailscaled startup must create its socket directory'

if grep -Eq 'tailscaled([[:space:]\\]|$)' "$CONNECT_SCRIPT" && \
   grep -Eq '&[[:space:]]+then' "$CONNECT_SCRIPT"; then
  fail 'background daemon startup must not use an asynchronous if condition'
fi

grep -Fq 'tailscale status --json' "$CONNECT_SCRIPT" || \
  fail 'daemon readiness must work before the node is logged in'

printf 'workflow security tests passed\n'
