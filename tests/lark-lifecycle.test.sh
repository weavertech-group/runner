#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
REPORTER="$ROOT_DIR/scripts/report-session-event.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

step_block() {
  local start="$1"
  local end="$2"
  sed -n "/- name: $start/,/- name: $end/p" "$WORKFLOW"
}

line_of() {
  grep -n -- "- name: $1" "$WORKFLOW" | head -n 1 | cut -d: -f1
}

for required in \
  'LARK_REPORTING_ENABLED: ${{ vars.LARK_REPORTING_ENABLED }}' \
  'LARK_WEBHOOK_URL: ${{ secrets.LARK_WEBHOOK_URL }}' \
  'LARK_WEBHOOK_SECRET: ${{ secrets.LARK_WEBHOOK_SECRET }}'; do
  grep -Fq "$required" "$WORKFLOW" || fail "missing Lark configuration mapping: $required"
done

if grep -Eq '^[[:space:]]+(LARK_WEBHOOK_URL|LARK_WEBHOOK_SECRET|LARK_REPORTING_ENABLED):' \
    <(sed -n '/workflow_dispatch:/,/run-name:/p' "$WORKFLOW"); then
  fail 'Lark destination or policy must not be a workflow input'
fi

starting_block="$(step_block 'Report session starting' 'Prepare network')"
ssh_block="$(step_block 'Report SSH online' 'Prepare repository access')"
status_block="$(step_block 'Report development environment status' 'Validate optional service prerequisites')"
offline_block="$(step_block 'Report session offline' 'Finalize')"

for block in "$starting_block" "$ssh_block" "$status_block" "$offline_block"; do
  grep -Fq 'continue-on-error: true' <<< "$block" || fail 'reporting step is not best effort'
  grep -Fq 'LARK_WEBHOOK_URL: ${{ secrets.LARK_WEBHOOK_URL }}' <<< "$block" || \
    fail 'reporting step does not use the fixed secret destination'
  if grep -Eq 'curl|open-apis/bot/v2/hook' <<< "$block"; then
    fail 'workflow must not construct Webhook requests directly'
  fi
done

grep -Fq 'run: bash scripts/report-session-event.sh starting' <<< "$starting_block" || \
  fail 'starting event is missing'
grep -Fq "if: \${{ inputs.enable_ssh && steps.connect.outcome == 'success' }}" <<< "$ssh_block" || \
  fail 'SSH event is not guarded by successful connection'
grep -Fq 'SESSION_RUNNER_NAME: gha-${{ github.run_id }}-${{ github.run_attempt }}' <<< "$ssh_block" || \
  fail 'safe runner name is missing'
grep -Fq 'bash scripts/report-session-event.sh setup-ready' <<< "$status_block" || \
  fail 'ready event is missing'
grep -Fq 'bash scripts/report-session-event.sh setup-degraded' <<< "$status_block" || \
  fail 'degraded event is missing'
grep -Fq 'run: bash scripts/report-session-event.sh offline' <<< "$offline_block" || \
  fail 'offline event is missing'

restore_line="$(line_of 'Restore npm download cache')"
starting_line="$(line_of 'Report session starting')"
network_line="$(line_of 'Prepare network')"
connect_line="$(line_of 'Connect')"
ssh_line="$(line_of 'Report SSH online')"
publish_line="$(line_of 'Publish development environment status')"
status_line="$(line_of 'Report development environment status')"
execute_line="$(line_of 'Execute')"
offline_line="$(line_of 'Report session offline')"
finalize_line="$(line_of 'Finalize')"

[[ "$restore_line" -lt "$starting_line" && "$starting_line" -lt "$network_line" ]] || \
  fail 'starting event must be after cache restore and before network setup'
[[ "$connect_line" -lt "$ssh_line" ]] || fail 'SSH event must follow connection'
[[ "$publish_line" -lt "$status_line" ]] || fail 'setup event must follow published status'
[[ "$execute_line" -lt "$offline_line" && "$offline_line" -lt "$finalize_line" ]] || \
  fail 'offline event must be attempted before cleanup'

grep -Fq 'id: connect' "$WORKFLOW" || fail 'Connect step needs a stable outcome ID'
if grep -Eq 'OWNER_TOKEN|PAIRING_URL|owner-token|pairing-url' \
    <<< "$starting_block$ssh_block$status_block$offline_block"; then
  fail 'ordinary lifecycle reporting references temporary service access material'
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export RUNNER_TEMP="$tmp/runner-temp"
export GITHUB_RUN_ID=123
export GITHUB_RUN_ATTEMPT=1
export GITHUB_REPOSITORY=weavertech-group/runner
export GITHUB_SERVER_URL=https://github.com
export SESSION_TARGET_ID=''
export SESSION_EVENT_NOW_EPOCH=1784600000
export LARK_REPORTING_ENABLED=false
bash "$REPORTER" starting >/dev/null 2>&1 || fail 'empty optional target was not normalized'

bash -n "$REPORTER" || fail 'reporter syntax failed'
printf 'Lark lifecycle workflow tests passed\n'
