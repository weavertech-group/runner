#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
SETUP_SCRIPT="$ROOT_DIR/scripts/setup-development-environment.sh"
CACHE_ACTION_SHA='55cc8345863c7cc4c66a329aec7e433d2d1c52a9'
CACHE_KEY="development-v1-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/development-versions.env') }}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail 'runner workflow is missing'
[[ -f "$SETUP_SCRIPT" ]] || fail 'development environment installer is missing'

grep -Fq "actions/cache/restore@${CACHE_ACTION_SHA}" "$WORKFLOW" || \
  fail 'development cache restore action is not pinned'
grep -Fq "actions/cache/save@${CACHE_ACTION_SHA}" "$WORKFLOW" || \
  fail 'development cache save action is not pinned'
[[ "$(grep -Fc "key: $CACHE_KEY" "$WORKFLOW")" -eq 2 ]] || \
  fail 'restore and save must use the exact version-derived cache key'
if grep -Fq 'restore-keys:' "$WORKFLOW"; then
  fail 'development cache must not restore a mismatched version prefix'
fi

for path in \
  '~/.local/share/mise/installs' \
  '~/.local/share/mise/shims' \
  '~/.cache/ms-playwright' \
  '~/go/bin/migrate' \
  '~/.local/bin/uv' \
  '~/.local/bin/uvx' \
  '~/.local/bin/mise'; do
  [[ "$(grep -Fc "$path" "$WORKFLOW")" -eq 2 ]] || \
    fail "cache path is not shared by restore and save: $path"
done

restore_block="$(sed -n '/- name: Restore development environment cache/,/- name: Install development environment/p' "$WORKFLOW")"
grep -Fq 'id: development-cache' <<< "$restore_block" || \
  fail 'development cache restore step lacks a stable ID'
grep -Fq 'continue-on-error: true' <<< "$restore_block" || \
  fail 'cache restore failure must not block a runner session'

install_block="$(sed -n '/- name: Install development environment/,/- name: Install Codex CLI/p' "$WORKFLOW")"
grep -Fq 'DEVELOPMENT_CACHE_HIT: ${{ steps.development-cache.outputs.cache-hit }}' \
  <<< "$install_block" || fail 'cache-hit state is not passed to the installer'

save_block="$(sed -n '/- name: Save development environment cache/,/- name: Execute/p' "$WORKFLOW")"
grep -Fq "if: \${{ steps.development-cache.outputs.cache-hit != 'true' }}" \
  <<< "$save_block" || fail 'cache save must run only after a cache miss'
grep -Fq 'continue-on-error: true' <<< "$save_block" || \
  fail 'cache save failure must not block a runner session'

save_line="$(grep -n -- '- name: Save development environment cache' "$WORKFLOW" | cut -d: -f1)"
execute_line="$(grep -n -- '- name: Execute' "$WORKFLOW" | cut -d: -f1)"
[[ "$save_line" -lt "$execute_line" ]] || \
  fail 'development cache must be saved before the long-running session step'

grep -Fq 'development_cache_hit="${DEVELOPMENT_CACHE_HIT:-false}"' "$SETUP_SCRIPT" || \
  fail 'installer does not consume the cache-hit state'
grep -Fq 'mise_cache_ready' "$SETUP_SCRIPT" || \
  fail 'installer does not validate restored mise toolchains'
grep -Fq '! -x "$HOME/go/bin/migrate"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached migration binary'
grep -Fq '! -x "$local_bin/uv"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached uv binary'
grep -Fq '! -x "$local_bin/mise"' "$SETUP_SCRIPT" || \
  fail 'installer does not reuse the cached mise binary'

bash -n "$SETUP_SCRIPT" || fail 'development environment installer has invalid shell syntax'

printf 'development cache tests passed\n'
