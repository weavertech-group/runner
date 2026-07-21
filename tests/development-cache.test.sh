#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
PREPARE_WORKFLOW="$ROOT_DIR/.github/workflows/prepare-development-cache.yml"
SETUP_SCRIPT="$ROOT_DIR/scripts/setup-development-environment.sh"
CACHE_ACTION_SHA='55cc8345863c7cc4c66a329aec7e433d2d1c52a9'
CACHE_KEY="development-v1-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/development-versions.env') }}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for file in "$WORKFLOW" "$PREPARE_WORKFLOW" "$SETUP_SCRIPT"; do
  [[ -f "$file" ]] || fail "required cache file is missing: $file"
done

for workflow in "$WORKFLOW" "$PREPARE_WORKFLOW"; do
  grep -Fq "actions/cache/restore@${CACHE_ACTION_SHA}" "$workflow" || \
    fail "cache restore action is not pinned: $workflow"
  grep -Fq "actions/cache/save@${CACHE_ACTION_SHA}" "$workflow" || \
    fail "cache save action is not pinned: $workflow"
  [[ "$(grep -Fc "key: $CACHE_KEY" "$workflow")" -eq 2 ]] || \
    fail "fixed cache key is not exact in $workflow"
  if grep -Fq 'restore-keys:' "$workflow"; then
    fail "cache must not restore a mismatched prefix: $workflow"
  fi

  for path in \
    '~/.local/share/mise/installs' \
    '~/.local/share/mise/shims' \
    '~/.cache/ms-playwright' \
    '~/.cache/private-runner/kubernetes' \
    '~/go/bin/migrate' \
    '~/.local/bin/uv' \
    '~/.local/bin/uvx' \
    '~/.local/bin/mise'; do
    [[ "$(grep -Fxc "            $path" "$workflow")" -eq 2 ]] || \
      fail "fixed cache path is not shared by restore and save: $path in $workflow"
  done

  for path in '~/.npm' '~/.cache/node/corepack'; do
    [[ "$(grep -Fxc "            $path" "$workflow")" -eq 2 ]] || \
      fail "npm cache path is not shared by restore and save: $path in $workflow"
  done

  grep -Fq 'npm-v1-${RUNNER_OS}-${RUNNER_ARCH}-node-${NODE_VERSION}-$(date -u +%G-W%V)' \
    "$workflow" || fail "weekly npm cache key is missing: $workflow"
  grep -Fq 'key: ${{ steps.cache-keys.outputs.npm }}' "$workflow" || \
    fail "npm cache does not use the generated key: $workflow"
done

restore_block="$(sed -n '/- name: Restore development environment cache/,/- name: Restore npm download cache/p' "$WORKFLOW")"
grep -Fq 'id: development-cache' <<< "$restore_block" || \
  fail 'development cache restore step lacks a stable ID'
grep -Fq 'continue-on-error: true' <<< "$restore_block" || \
  fail 'development cache restore failure must not block a runner session'

npm_restore_block="$(sed -n '/- name: Restore npm download cache/,/- name: Prepare network/p' "$WORKFLOW")"
grep -Fq 'id: npm-cache' <<< "$npm_restore_block" || \
  fail 'npm cache restore step lacks a stable ID'
grep -Fq 'continue-on-error: true' <<< "$npm_restore_block" || \
  fail 'npm cache restore failure must not block a runner session'

install_block="$(sed -n '/- name: Install development environment/,/- name: Verify fixed development environment/p' "$WORKFLOW")"
grep -Fq 'DEVELOPMENT_CACHE_HIT: ${{ steps.development-cache.outputs.cache-hit }}' \
  <<< "$install_block" || fail 'cache-hit state is not passed to the installer'

fixed_save_line="$(grep -n -- '- name: Save development environment cache' "$WORKFLOW" | cut -d: -f1)"
ai_install_line="$(grep -n -- '- name: Install AI coding CLIs' "$WORKFLOW" | cut -d: -f1)"
devspace_line="$(grep -n -- '- name: Start optional service' "$WORKFLOW" | cut -d: -f1)"
[[ "$fixed_save_line" -lt "$ai_install_line" && "$fixed_save_line" -lt "$devspace_line" ]] || \
  fail 'fixed development cache is not saved immediately after fixed verification'

fixed_save_block="$(sed -n '/- name: Save development environment cache/,/- name: Install AI coding CLIs/p' "$WORKFLOW")"
grep -Fq "steps.development-install.outcome == 'success'" <<< "$fixed_save_block" || \
  fail 'fixed cache save is not guarded by installation success'
grep -Fq "steps.fixed-verify.outcome == 'success'" <<< "$fixed_save_block" || \
  fail 'fixed cache save is not guarded by verification success'
grep -Fq 'continue-on-error: true' <<< "$fixed_save_block" || \
  fail 'fixed cache save failure must not block a session'

npm_save_block="$(sed -n '/- name: Save npm download cache/,/- name: Publish development environment status/p' "$WORKFLOW")"
grep -Fq "steps.ai-tools.outcome == 'success'" <<< "$npm_save_block" || \
  fail 'npm cache save is not guarded by AI CLI installation success'
grep -Fq 'continue-on-error: true' <<< "$npm_save_block" || \
  fail 'npm cache save failure must not block a session'

grep -Fq 'development_cache_hit="${DEVELOPMENT_CACHE_HIT:-false}"' "$SETUP_SCRIPT" || \
  fail 'installer does not consume the cache-hit state'
grep -Fq 'mise_cache_ready' "$SETUP_SCRIPT" || \
  fail 'installer does not validate restored mise toolchains'
grep -Fq 'browser_cache_ready' "$SETUP_SCRIPT" || \
  fail 'installer does not recognize a restored Playwright browser'
grep -Fq 'playwright install-deps chromium' "$SETUP_SCRIPT" || \
  fail 'cached Playwright browsers do not skip browser downloads'
grep -Fq 'kubernetes_cache_dir=' "$SETUP_SCRIPT" || \
  fail 'Kubernetes downloads are not stored in the fixed cache'
grep -Fq '! -x "$HOME/go/bin/migrate"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached migration binary'
grep -Fq '! -x "$local_bin/uv"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached uv binary'
grep -Fq '! -x "$local_bin/mise"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached mise binary'

bash -n "$SETUP_SCRIPT" || fail 'development environment installer has invalid shell syntax'

printf 'development cache tests passed\n'
