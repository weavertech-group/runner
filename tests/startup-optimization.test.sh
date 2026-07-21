#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
PREPARE_WORKFLOW="$ROOT_DIR/.github/workflows/prepare-development-cache.yml"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-development-environment.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for file in "$WORKFLOW" "$PREPARE_WORKFLOW" "$VERIFY_SCRIPT"; do
  [[ -f "$file" ]] || fail "startup optimization file is missing: $file"
done

connect_line="$(grep -n -- '- name: Connect' "$WORKFLOW" | head -n 1 | cut -d: -f1)"
install_line="$(grep -n -- '- name: Install development environment' "$WORKFLOW" | cut -d: -f1)"
[[ "$connect_line" -lt "$install_line" ]] || \
  fail 'private SSH is not established before full development setup'

repository_line="$(grep -n -- '- name: Prepare repository access' "$WORKFLOW" | cut -d: -f1)"
[[ "$repository_line" -lt "$install_line" ]] || \
  fail 'repository access is not available while development setup runs'

ai_block="$(sed -n '/- name: Install AI coding CLIs/,/- name: Verify complete development environment/p' "$WORKFLOW")"
grep -Fq '@openai/codex@latest' <<< "$ai_block" || \
  fail 'combined AI installation does not include latest Codex'
grep -Fq '@anthropic-ai/claude-code@latest' <<< "$ai_block" || \
  fail 'combined AI installation does not include latest Claude Code'
[[ "$(grep -Fc 'npm install' <<< "$ai_block")" -eq 1 ]] || \
  fail 'Codex and Claude do not share one npm install invocation'

grep -Fq 'id: development-install' "$WORKFLOW" || \
  fail 'development installation outcome is not tracked'
grep -Fq 'id: ai-tools' "$WORKFLOW" || \
  fail 'AI installation outcome is not tracked'
grep -Fq 'id: complete-verify' "$WORKFLOW" || \
  fail 'complete environment verification outcome is not tracked'

for step in 'Install development environment' 'Install AI coding CLIs' \
  'Verify complete development environment'; do
  block="$(sed -n "/- name: $step/,/- name:/p" "$WORKFLOW" | head -n -1)"
  grep -Fq 'continue-on-error: true' <<< "$block" || \
    fail "$step must leave the SSH session available for manual repair"
done

grep -Fq "status=degraded" "$WORKFLOW" || \
  fail 'degraded setup status is not published'
grep -Fq "status=ready" "$WORKFLOW" || \
  fail 'ready setup status is not published'
grep -Fq 'private-runner-session/setup-status' "$WORKFLOW" || \
  fail 'setup status file is not written'
grep -Fq 'private-runner-session/setup-details' "$WORKFLOW" || \
  fail 'setup outcome details are not written'

grep -Fq 'VERIFY_AI_TOOLS: false' "$WORKFLOW" || \
  fail 'fixed tools are not verified before AI CLI installation'
grep -Fq 'verify_ai_tools="${VERIFY_AI_TOOLS:-true}"' "$VERIFY_SCRIPT" || \
  fail 'environment verifier cannot skip AI tools for fixed-cache validation'

execute_line="$(grep -n -- '- name: Execute' "$WORKFLOW" | cut -d: -f1)"
status_line="$(grep -n -- '- name: Publish development environment status' "$WORKFLOW" | cut -d: -f1)"
[[ "$status_line" -lt "$execute_line" ]] || \
  fail 'setup status is not published before the long-running session'

service_prerequisite_block="$(sed -n '/- name: Validate optional service prerequisites/,/- name: Install optional service tools/p' "$WORKFLOW")"
grep -Fq '"$ENABLE_DEVSPACE" == true && "$FIXED_VERIFY" != success' \
  <<< "$service_prerequisite_block" || \
  fail 'DevSpace is not guarded by a usable fixed development environment'
grep -Fq '"$ENABLE_T3CODE" == true && "$COMPLETE_VERIFY" != success' \
  <<< "$service_prerequisite_block" || \
  fail 'T3 Code is not guarded by a complete coding-agent environment'

[[ "$(grep -Fc 'workflow_dispatch:' "$PREPARE_WORKFLOW")" -eq 1 ]] || \
  fail 'cache preparation workflow must be manually dispatchable'
if grep -Eq '^[[:space:]]+(push|pull_request|schedule|workflow_run|repository_dispatch):' \
  "$PREPARE_WORKFLOW"; then
  fail 'cache preparation workflow must remain manual only'
fi
grep -Fq 'bash scripts/setup-development-environment.sh' "$PREPARE_WORKFLOW" || \
  fail 'cache preparation workflow does not build the development environment'
grep -Fq 'bash scripts/verify-development-environment.sh' "$PREPARE_WORKFLOW" || \
  fail 'cache preparation workflow does not verify the development environment'

bash -n "$VERIFY_SCRIPT" || fail 'development verifier has invalid shell syntax'

printf 'startup optimization tests passed\n'
