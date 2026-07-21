#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="$ROOT_DIR/.github/workflows/repo-01-t3code-session.yml"
SMOKE="$ROOT_DIR/.github/workflows/repo-01-t3code-smoke.yml"
MARKER="$ROOT_DIR/.github/repo-01-t3code-smoke.pending"
PRIVATE_WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
CLOUDFLARED_INSTALLER="$ROOT_DIR/scripts/install-cloudflared.sh"
ALLOWLIST="$ROOT_DIR/.github/target-repositories.txt"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for path in "$PRESET" "$SMOKE" "$MARKER" "$PRIVATE_WORKFLOW" "$CLOUDFLARED_INSTALLER"; do
  [[ -f "$path" ]] || fail "required preset file is missing: $path"
done

[[ "$(grep -Fc 'workflow_dispatch:' "$PRESET")" -eq 1 ]] || \
  fail 'preset must expose exactly one manual trigger'
if grep -Eq '^[[:space:]]+(pull_request|pull_request_target|push|issue_comment|workflow_run|repository_dispatch|schedule):' \
    "$PRESET"; then
  fail 'preset must remain manually dispatched only'
fi

trigger_block="$(sed -n '/^on:/,/^run-name:/p' "$PRESET")"
if grep -Fq 'inputs:' <<< "$trigger_block"; then
  fail 'preset must not expose operator inputs'
fi

grep -Fq 'actions: write' "$PRESET" || fail 'preset needs Actions write permission to dispatch'
grep -Fq 'contents: read' "$PRESET" || fail 'preset must keep contents read-only'
grep -Fq 'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' "$PRESET" || \
  fail 'preset does not use the ephemeral repository token'
grep -Fq 'gh workflow run private-runner-session.yml' "$PRESET" || \
  fail 'preset does not dispatch the shared private runner workflow'
grep -Fq -- '--ref main' "$PRESET" || fail 'preset must dispatch the protected main workflow'

grep -Fq -- '--raw-field target_id=repo-01' "$PRESET" || fail 'preset target is not repo-01'
grep -Fq -- '--raw-field enable_ssh=true' "$PRESET" || fail 'preset must enable SSH'
grep -Fq -- '--raw-field enable_devspace=false' "$PRESET" || fail 'preset must disable DevSpace'
grep -Fq -- '--raw-field enable_t3code=true' "$PRESET" || fail 'preset must enable T3 Code'

if grep -Eq '(^|[[:space:]])(set -x|printenv|env)([[:space:]]|$)' "$PRESET"; then
  fail 'preset contains a command that can expose credentials'
fi
if grep -Eq 'HEADSCALE_AUTHKEY|TARGET_REPO_AUTH|LARK_WEBHOOK_(URL|SECRET)' "$PRESET"; then
  fail 'preset must not handle private session credentials directly'
fi

# The temporary smoke workflow is deliberately constrained to the reviewed marker
# addition on main. It must verify T3/Lark readiness, report its run IDs, and clean up.
grep -Fq 'name: Repo 01 T3 Code Smoke' "$SMOKE" || fail 'smoke workflow name changed'
grep -Fq 'branches:' "$SMOKE" || fail 'smoke trigger lacks branch restriction'
grep -Fq '      - main' "$SMOKE" || fail 'smoke trigger is not limited to main'
grep -Fq '      - .github/repo-01-t3code-smoke.pending' "$SMOKE" || \
  fail 'smoke trigger is not limited to the one-time marker'
grep -Fq "if: \${{ github.repository == 'weavertech-group/runner' }}" "$SMOKE" || \
  fail 'smoke workflow lacks repository guard'
grep -Fq 'actions: write' "$SMOKE" || fail 'smoke cannot manage the downstream run'
grep -Fq 'issues: write' "$SMOKE" || fail 'smoke cannot report auditable status'
grep -Fq 'timeout-minutes: 45' "$SMOKE" || fail 'smoke workflow lacks a bounded timeout'
grep -Fq 'gh workflow run private-runner-session.yml' "$SMOKE" || \
  fail 'smoke workflow does not dispatch the shared workflow'
grep -Fq -- '--raw-field target_id=repo-01' "$SMOKE" || fail 'smoke target is not repo-01'
grep -Fq -- '--raw-field enable_ssh=true' "$SMOKE" || fail 'smoke must enable SSH'
grep -Fq -- '--raw-field enable_devspace=false' "$SMOKE" || fail 'smoke must disable DevSpace'
grep -Fq -- '--raw-field enable_t3code=true' "$SMOKE" || fail 'smoke must enable T3 Code'
grep -Fq 'Verify public T3 Code' "$SMOKE" || fail 'smoke does not wait for public T3 readiness'
grep -Fq 'Report optional services online' "$SMOKE" || fail 'smoke does not wait for Lark reporting'
grep -Fq 'gh issue comment 24' "$SMOKE" || fail 'smoke does not report status to issue 24'
grep -Fq "grep -oE 'E(51|61)'" "$SMOKE" || fail 'smoke does not report the stable tool failure code'
grep -Fq 'gh run cancel "$RUN_ID"' "$SMOKE" || fail 'smoke does not cancel the session'
grep -Fq '$steps["Finalize"]' "$SMOKE" || fail 'smoke does not verify final cleanup'

if grep -Eq 'HEADSCALE_AUTHKEY|TARGET_REPO_AUTH|LARK_WEBHOOK_(URL|SECRET)' "$SMOKE"; then
  fail 'smoke workflow must not handle downstream credentials directly'
fi

grep -Fq -- '--connect-timeout 15' "$CLOUDFLARED_INSTALLER" || \
  fail 'cloudflared download lacks a connection timeout'
grep -Fq -- '--max-time 180' "$CLOUDFLARED_INSTALLER" || \
  fail 'cloudflared download lacks a total timeout'
grep -Fq -- '--retry 8' "$CLOUDFLARED_INSTALLER" || \
  fail 'cloudflared download retry count is too low'
grep -Fq -- '--retry-all-errors' "$CLOUDFLARED_INSTALLER" || \
  fail 'cloudflared download does not retry all transient errors'
grep -Fq 'sha256sum --check --status' "$CLOUDFLARED_INSTALLER" || \
  fail 'cloudflared checksum verification was removed'

grep -Eq '^repo-01[[:space:]]+session--repo-01$' "$ALLOWLIST" || \
  fail 'repo-01 is not mapped to its target Environment'
grep -Fq 'workflow_dispatch:' "$PRIVATE_WORKFLOW" || \
  fail 'shared private runner workflow is not manually dispatchable'

printf 'repo-01 T3 Code preset tests passed\n'
