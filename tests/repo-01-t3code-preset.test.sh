#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="$ROOT_DIR/.github/workflows/repo-01-t3code-session.yml"
PRIVATE_WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
ALLOWLIST="$ROOT_DIR/.github/target-repositories.txt"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$PRESET" ]] || fail 'repo-01 T3 Code preset workflow is missing'
[[ -f "$PRIVATE_WORKFLOW" ]] || fail 'private runner workflow is missing'

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

grep -Eq '^repo-01[[:space:]]+session--repo-01$' "$ALLOWLIST" || \
  fail 'repo-01 is not mapped to its target Environment'
grep -Fq 'workflow_dispatch:' "$PRIVATE_WORKFLOW" || \
  fail 'shared private runner workflow is not manually dispatchable'

printf 'repo-01 T3 Code preset tests passed\n'
