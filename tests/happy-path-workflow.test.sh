#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"

grep -Fq 'npm install --global --no-audit --no-fund t3@0.0.28' "$WORKFLOW"
grep -Fq 'npm install --global --no-audit --no-fund @waishnav/devspace@1.0.4' "$WORKFLOW"
grep -Fq 'cloudflared-linux-amd64' "$WORKFLOW"
grep -Fq 't3 serve --base-dir' "$WORKFLOW"
grep -Fq 'devspace serve' "$WORKFLOW"
grep -Fq 'run: sleep infinity' "$WORKFLOW"
grep -Fq '[[ -n "$environment_name" ]]' "$WORKFLOW"
grep -Fq 'AddressFamily inet6' "$WORKFLOW"
grep -Fq 'ListenAddress %s' "$WORKFLOW"
grep -Fq 'inputs.enable_ssh && inputs.target_id !=' "$WORKFLOW"

if rg -q 'bash scripts/(install|connect|start|verify|cleanup|prepare|configure|session-lib)' "$WORKFLOW"; then
  exit 1
fi

printf '%s\n' 'happy-path workflow tests passed'
