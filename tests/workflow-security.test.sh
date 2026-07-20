#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
CONNECT_SCRIPT="$ROOT_DIR/scripts/connect-headscale.sh"
ALLOWLIST="$ROOT_DIR/.github/target-repositories.txt"
CODEOWNERS="$ROOT_DIR/.github/CODEOWNERS"
SECURITY_POLICY="$ROOT_DIR/SECURITY.md"
CLOUDFLARED_SCRIPT="$ROOT_DIR/scripts/install-cloudflared.sh"
DEVSPACE_SCRIPT="$ROOT_DIR/scripts/start-devspace.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail 'workflow is missing'
[[ -f "$CODEOWNERS" ]] || fail 'CODEOWNERS is missing'
[[ -f "$SECURITY_POLICY" ]] || fail 'security policy is missing'
[[ -f "$CLOUDFLARED_SCRIPT" ]] || fail 'cloudflared installer is missing'
[[ -f "$DEVSPACE_SCRIPT" ]] || fail 'DevSpace launcher is missing'

grep -Fq 'workflow_dispatch:' "$WORKFLOW" || \
  fail 'privileged workflow must remain manually dispatched'
if grep -Eq '^[[:space:]]+(pull_request|pull_request_target|push|issue_comment|workflow_run|repository_dispatch|schedule):' \
  "$WORKFLOW"; then
  fail 'privileged workflow must not gain an automatic or fork-driven trigger'
fi

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

if grep -Fq 'HEADSCALE_MAGIC_DNS_DOMAIN' "$WORKFLOW"; then
  fail 'runner workflow must not depend on a MagicDNS domain secret'
fi

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

grep -Fq '/.github/ @ronhuafeng' "$CODEOWNERS" || \
  fail 'security-sensitive GitHub configuration lacks an explicit code owner'
grep -Fq '/SECURITY.md @ronhuafeng' "$CODEOWNERS" || \
  fail 'security policy lacks an explicit code owner'

grep -Fq 'openssh-server' "$CONNECT_SCRIPT" || \
  fail 'fallback mode must install the SSH server explicitly'

grep -Fq 'ListenAddress %s' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must bind only to the Tailscale address'

grep -Fq 'AddressFamily inet6' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must use the IPv6-only tailnet path'

if grep -Fq 'tailnet_ipv4' "$CONNECT_SCRIPT"; then
  fail 'fallback SSH must not depend on conflicting CGNAT routes'
fi

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

grep -Fq -- '--accept-dns=false' "$CONNECT_SCRIPT" || \
  fail 'runner must not install tailnet DNS settings'

if grep -Eq 'HEADSCALE_MAGIC_DNS_DOMAIN|DNSName|runner-fqdn' "$CONNECT_SCRIPT"; then
  fail 'runner connection must not validate or persist MagicDNS names'
fi

grep -Fq 'enable_devspace:' "$WORKFLOW" || \
  fail 'DevSpace must remain an explicit workflow opt-in'
grep -Fq 'actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020' "$WORKFLOW" || \
  fail 'DevSpace Node runtime action is not pinned'
grep -Fq 'node-version: 22.19.0' "$WORKFLOW" || \
  fail 'DevSpace Node runtime version is not fixed'
grep -Fq 'bash scripts/install-cloudflared.sh' "$WORKFLOW" || \
  fail 'workflow does not install the pinned tunnel binary'
grep -Fq 'bash scripts/start-devspace.sh' "$WORKFLOW" || \
  fail 'workflow does not start DevSpace'

if grep -Eq 'GITHUB_OUTPUT.*(MCP|DEVSPACE|OWNER|PUBLIC)' "$WORKFLOW"; then
  fail 'DevSpace connection material must not use workflow outputs'
fi

grep -Fq "version='2026.7.2'" "$CLOUDFLARED_SCRIPT" || \
  fail 'cloudflared version is not pinned'
grep -Fq "sha256='ec905ea7b7e327ff8abdde8cb64697a2152de74dbcdbf6aec9db8364eb3886cd'" \
  "$CLOUDFLARED_SCRIPT" || fail 'cloudflared checksum is not pinned'
grep -Fq 'sha256sum --check --status' "$CLOUDFLARED_SCRIPT" || \
  fail 'cloudflared download is not checksum verified'

grep -Fq "devspace_package='@waishnav/devspace@1.0.4'" "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace package version is not pinned'
grep -Fq 'DEVSPACE_ALLOWED_ROOTS="$workspace"' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace filesystem scope is not restricted to the cloned workspace'
grep -Fq 'DEVSPACE_SUBAGENTS=0' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace subagents must be disabled by default'
grep -Fq 'connection.txt' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace connection material is not written locally'
grep -Fq 'chmod 0600' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace connection material does not receive private permissions'

if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$DEVSPACE_SCRIPT"; then
  fail 'DevSpace launcher contains a command that can expose secrets'
fi

grep -Fq 'devspace.pid' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not terminate DevSpace'
grep -Fq 'cloudflared.pid' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not terminate cloudflared'
grep -Fq 'private-runner-session/devspace' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not remove local connection material'

printf 'workflow security tests passed\n'
