#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"

grep -Fq 'npx --yes t3@latest serve' "$WORKFLOW"
grep -Fq 'npx --yes @waishnav/devspace@latest serve' "$WORKFLOW"
grep -Fq 'https://chatgpt.com/codex/install.sh' "$WORKFLOW"
grep -Fq 'https://claude.ai/install.sh' "$WORKFLOW"
grep -Fq 'cloudflared-linux-amd64' "$WORKFLOW"
grep -Fq 'releases/latest/download/cloudflared-linux-amd64' "$WORKFLOW"
grep -Fq 'Pairing URL: ' "$WORKFLOW"
grep -Fq 'run: sleep infinity' "$WORKFLOW"
grep -Fq '[[ -n "$environment_name" ]]' "$WORKFLOW"
grep -Fq 'AddressFamily inet6' "$WORKFLOW"
grep -Fq 'ListenAddress %s' "$WORKFLOW"
grep -Fq 'inputs.enable_ssh && inputs.target_id !=' "$WORKFLOW"

if rg -q 'bash scripts/(install|connect|start|verify|cleanup|prepare|configure|session-lib)' "$WORKFLOW"; then
  exit 1
fi

if rg -q 'T3CODE_HOME|--base-dir|project add|DEVSPACE_(CONFIG|STATE|WORKTREE)_ROOT' "$WORKFLOW"; then
  exit 1
fi

printf '%s\n' 'happy-path workflow tests passed'
