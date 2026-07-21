#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
PREPARE_WORKSPACE="$ROOT_DIR/scripts/prepare-target-workspace.sh"
INSTALL_T3="$ROOT_DIR/scripts/install-t3code.sh"
START_DEVSPACE="$ROOT_DIR/scripts/start-devspace.sh"
START_T3="$ROOT_DIR/scripts/start-t3code.sh"
START_TUNNEL="$ROOT_DIR/scripts/start-cloudflare-tunnel.sh"
VERIFY_PUBLIC="$ROOT_DIR/scripts/verify-public-services.sh"
CLEANUP="$ROOT_DIR/scripts/cleanup.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for file in "$WORKFLOW" "$PREPARE_WORKSPACE" "$INSTALL_T3" "$START_DEVSPACE" \
  "$START_T3" "$START_TUNNEL" "$VERIFY_PUBLIC" "$CLEANUP"; do
  [[ -f "$file" ]] || fail "required remote-service file is missing: $file"
done

grep -Fq 'enable_t3code:' "$WORKFLOW" || \
  fail 'T3 Code must remain an explicit workflow opt-in'
grep -Fq 'group: private-runner-${{ inputs.target_id || github.run_id }}' "$WORKFLOW" || \
  fail 'opaque targets must be serialized by concurrency group'
grep -Fq '(inputs.enable_devspace || inputs.enable_t3code)' "$WORKFLOW" || \
  fail 'optional service validation does not cover T3 Code'
grep -Fq 'CLOUDFLARE_TUNNEL_TOKEN: ${{ secrets.CLOUDFLARE_TUNNEL_TOKEN }}' "$WORKFLOW" || \
  fail 'named tunnel token is not Environment-scoped'
grep -Fq 'T3_PUBLIC_URL: ${{ secrets.T3_PUBLIC_URL }}' "$WORKFLOW" || \
  fail 'T3 public URL is not Environment-scoped'
grep -Fq 'DEVSPACE_PUBLIC_URL: ${{ secrets.DEVSPACE_PUBLIC_URL }}' "$WORKFLOW" || \
  fail 'DevSpace public URL is not Environment-scoped'
if grep -Eq 'GITHUB_OUTPUT.*(T3|PAIRING|TUNNEL|DEVSPACE|OWNER|PUBLIC)' "$WORKFLOW"; then
  fail 'remote connection material must not use workflow outputs'
fi

grep -Fq 'target-workspace' "$START_DEVSPACE" || \
  fail 'DevSpace does not use the shared target workspace'
grep -Fq 'target-workspace' "$START_T3" || \
  fail 'T3 Code does not use the shared target workspace'
grep -Fq 'git clone --quiet' "$PREPARE_WORKSPACE" || \
  fail 'target workspace is not prepared centrally'
if grep -Fq 'git clone' "$START_DEVSPACE" || grep -Fq 'git clone' "$START_T3"; then
  fail 'service launchers must not create independent clones'
fi

grep -Fq "t3_package='t3@0.0.28'" "$INSTALL_T3" || \
  fail 'T3 Code package version is not pinned'
grep -Fq '"$t3_bin" project add' "$START_T3" || \
  fail 'T3 project is not initialized explicitly'
grep -Fq -- '--host 127.0.0.1' "$START_T3" || \
  fail 'T3 Code must bind to loopback'
grep -Fq -- '--port 3773' "$START_T3" || \
  fail 'T3 Code does not use the configured tunnel origin port'
grep -Fq 'PAIRING_URL=' "$START_T3" || \
  fail 'T3 pairing details are not written to a private file'
grep -Fq 'chmod 0600' "$START_T3" || \
  fail 'T3 connection material does not receive private permissions'

if grep -Fq 'trycloudflare.com' "$START_TUNNEL" "$START_DEVSPACE"; then
  fail 'Quick Tunnel behavior must not remain in named-tunnel launchers'
fi
grep -Fq -- '--token-file "$token_file"' "$START_TUNNEL" || \
  fail 'cloudflared must consume the tunnel credential from a file'
grep -Fq 'unset CLOUDFLARE_TUNNEL_TOKEN' "$START_TUNNEL" || \
  fail 'tunnel token remains in the cloudflared process environment'
grep -Fq '"${devspace_public_url%/}" == "${t3_public_url%/}"' "$START_TUNNEL" || \
  fail 'T3 Code and DevSpace must not share one hostname'
grep -Fq 'new WebSocket' "$VERIFY_PUBLIC" || \
  fail 'public T3 readiness does not verify WebSocket upgrades'

grep -Fq 'cloudflared-token' "$CLEANUP" || \
  fail 'cleanup does not remove the tunnel token file'
grep -Fq 't3code.pid' "$CLEANUP" || \
  fail 'cleanup does not terminate T3 Code'
grep -Fq 'private-runner-session/t3code' "$START_T3" || \
  fail 'T3 connection material is not stored under the private session directory'

for script in "$PREPARE_WORKSPACE" "$INSTALL_T3" "$START_DEVSPACE" "$START_T3" \
  "$START_TUNNEL" "$VERIFY_PUBLIC" "$CLEANUP"; do
  bash -n "$script" || fail "shell syntax check failed: $script"
  if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$script"; then
    fail "remote service script can expose secrets: $script"
  fi
done

printf 'remote service security tests passed\n'
