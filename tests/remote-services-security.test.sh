#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
PREPARE_WORKSPACE="$ROOT_DIR/scripts/prepare-target-workspace.sh"
INSTALL_T3="$ROOT_DIR/scripts/install-t3code.sh"
START_DEVSPACE="$ROOT_DIR/scripts/start-devspace.sh"
START_T3="$ROOT_DIR/scripts/start-t3code.sh"
START_TUNNELS="$ROOT_DIR/scripts/start-quick-tunnels.sh"
VERIFY_PUBLIC="$ROOT_DIR/scripts/verify-public-services.sh"
CLEANUP="$ROOT_DIR/scripts/cleanup.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for file in "$WORKFLOW" "$PREPARE_WORKSPACE" "$INSTALL_T3" "$START_DEVSPACE" \
  "$START_T3" "$START_TUNNELS" "$VERIFY_PUBLIC" "$CLEANUP"; do
  [[ -f "$file" ]] || fail "required remote-service file is missing: $file"
done

forbidden_named_tunnel='Named'' Tunnel'
forbidden_tunnel_token='CLOUDFLARE_''TUNNEL_TOKEN'
forbidden_t3_url='T3_''PUBLIC_URL'
forbidden_devspace_url='DEVSPACE_''PUBLIC_URL'
if grep -R -F -e "$forbidden_named_tunnel" \
  -e "$forbidden_tunnel_token" \
  -e "$forbidden_t3_url" \
  -e "$forbidden_devspace_url" \
  "$ROOT_DIR/.github" "$ROOT_DIR/scripts" "$ROOT_DIR/docs" \
  "$ROOT_DIR/README.md" "$ROOT_DIR/SECURITY.md" >/dev/null; then
  fail 'obsolete fixed-tunnel configuration remains in live files or documentation'
fi

[[ ! -e "$ROOT_DIR/scripts/start-cloudflare-tunnel.sh" ]] || \
  fail 'obsolete fixed-tunnel launcher still exists'
[[ ! -e "$ROOT_DIR/tests/named-tunnel.test.sh" ]] || \
  fail 'obsolete fixed-tunnel test still exists'

grep -Fq 'enable_t3code:' "$WORKFLOW" || \
  fail 'T3 Code must remain an explicit workflow opt-in'
grep -Fq 'group: private-runner-${{ github.run_id }}' "$WORKFLOW" || \
  fail 'Quick Tunnel sessions must remain independent by workflow run'
grep -Fq '(inputs.enable_devspace || inputs.enable_t3code)' "$WORKFLOW" || \
  fail 'optional service validation does not cover T3 Code'
grep -Fq 'bash scripts/start-quick-tunnels.sh' "$WORKFLOW" || \
  fail 'workflow does not start Quick Tunnels'
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
  fail 'T3 Code does not use the Quick Tunnel origin port'
grep -Fq 'PAIRING_URL=' "$START_T3" || \
  fail 'T3 pairing details are not written to a private file'
grep -Fq 'chmod 0600' "$START_T3" || \
  fail 'T3 connection material does not receive private permissions'

grep -Fq -- '--url "$origin"' "$START_TUNNELS" || \
  fail 'Quick Tunnel command does not use the selected local origin'
grep -Fq 'http://127.0.0.1:7676' "$START_TUNNELS" || \
  fail 'DevSpace Quick Tunnel origin is missing'
grep -Fq 'http://127.0.0.1:3773' "$START_TUNNELS" || \
  fail 'T3 Quick Tunnel origin is missing'
grep -Fq 'trycloudflare[.]com' "$START_TUNNELS" || \
  fail 'Quick Tunnel URL discovery is missing'
grep -Fq 'cloudflared-devspace.pid' "$CLEANUP" || \
  fail 'cleanup does not terminate the DevSpace Quick Tunnel'
grep -Fq 'cloudflared-t3code.pid' "$CLEANUP" || \
  fail 'cleanup does not terminate the T3 Quick Tunnel'
grep -Fq 'devspace-public-url' "$START_DEVSPACE" || \
  fail 'DevSpace does not consume its generated Quick Tunnel URL'
grep -Fq 't3code-public-url' "$START_T3" || \
  fail 'T3 Code does not consume its generated Quick Tunnel URL'
grep -Fq 'new WebSocket' "$VERIFY_PUBLIC" || \
  fail 'public T3 readiness does not verify WebSocket upgrades'

grep -Fq 't3code.pid' "$CLEANUP" || \
  fail 'cleanup does not terminate T3 Code'
grep -Fq 'private-runner-session/t3code' "$START_T3" || \
  fail 'T3 connection material is not stored under the private session directory'

for script in "$PREPARE_WORKSPACE" "$INSTALL_T3" "$START_DEVSPACE" "$START_T3" \
  "$START_TUNNELS" "$VERIFY_PUBLIC" "$CLEANUP"; do
  bash -n "$script" || fail "shell syntax check failed: $script"
  if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$script"; then
    fail "remote service script can expose secrets: $script"
  fi
done

printf 'remote service security tests passed\n'
