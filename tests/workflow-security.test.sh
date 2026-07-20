#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/private-runner-session.yml"
CONNECT_SCRIPT="$ROOT_DIR/scripts/connect-headscale.sh"
ALLOWLIST="$ROOT_DIR/.github/target-repositories.txt"
CODEOWNERS="$ROOT_DIR/.github/CODEOWNERS"
SECURITY_POLICY="$ROOT_DIR/SECURITY.md"
CLOUDFLARED_SCRIPT="$ROOT_DIR/scripts/install-cloudflared.sh"
DEVSPACE_SCRIPT="$ROOT_DIR/scripts/start-devspace.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup.sh"
DEVELOPMENT_SETUP="$ROOT_DIR/scripts/setup-development-environment.sh"
DEVELOPMENT_VERIFY="$ROOT_DIR/scripts/verify-development-environment.sh"
DEVELOPMENT_VERSIONS="$ROOT_DIR/scripts/development-versions.env"
PROJECT_BOOTSTRAP="$ROOT_DIR/scripts/bootstrap-project.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "$2"
}

require_unconditional_step() {
  local start="$1"
  local end="$2"
  local message="$3"
  local block=''
  block="$(sed -n "/- name: $start/,/- name: $end/p" "$WORKFLOW")"
  [[ -n "$block" ]] || fail "$message is missing"
  if grep -Fq 'if:' <<< "$block"; then
    fail "$message must run for every valid runner session"
  fi
}

require_file "$WORKFLOW" 'workflow is missing'
require_file "$CODEOWNERS" 'CODEOWNERS is missing'
require_file "$SECURITY_POLICY" 'security policy is missing'
require_file "$CLOUDFLARED_SCRIPT" 'cloudflared installer is missing'
require_file "$DEVSPACE_SCRIPT" 'DevSpace launcher is missing'
require_file "$DEVELOPMENT_SETUP" 'development environment installer is missing'
require_file "$DEVELOPMENT_VERIFY" 'development environment verifier is missing'
require_file "$DEVELOPMENT_VERSIONS" 'development version manifest is missing'
require_file "$PROJECT_BOOTSTRAP" 'project bootstrap command is missing'

grep -Fq 'workflow_dispatch:' "$WORKFLOW" || \
  fail 'privileged workflow must remain manually dispatched'
if grep -Eq '^[[:space:]]+(pull_request|pull_request_target|push|issue_comment|workflow_run|repository_dispatch|schedule):' \
  "$WORKFLOW"; then
  fail 'privileged workflow must not gain an automatic or fork-driven trigger'
fi

if grep -Eq 'uses: [^@]+@(main|master|v[0-9]+([.]?[0-9]+)*)$' "$WORKFLOW"; then
  fail 'third-party actions must be pinned to a full commit SHA'
fi

if grep -Eq '(^|[[:space:]])(set -x|env|printenv)([[:space:]]|$)' "$WORKFLOW"; then
  fail 'workflow contains a command that can expose secrets'
fi

grep -Fq 'TARGET_REPO_AUTH: ${{ secrets.TARGET_REPO_AUTH }}' "$WORKFLOW" || \
  fail 'selected repository credential is not scoped explicitly'

grep -Fq "if: \${{ inputs.target_id != '' }}" "$WORKFLOW" || \
  fail 'repository credential is referenced without an input guard'

grep -Fq 'TARGET_REPO: ${{ secrets.TARGET_REPO }}' "$WORKFLOW" || \
  fail 'real repository identity must come from the selected Environment'

grep -Fq 'HEADSCALE_URL: ${{ secrets.HEADSCALE_URL }}' "$WORKFLOW" || \
  fail 'Headscale URL must be masked as sensitive metadata'

if grep -Fq 'HEADSCALE_MAGIC_DNS_DOMAIN' "$WORKFLOW"; then
  fail 'runner workflow must not depend on a MagicDNS domain secret'
fi

grep -Fq 'deployment: false' "$WORKFLOW" || \
  fail 'session jobs must not create public deployment records'

grep -Fq 'timeout-minutes: 360' "$WORKFLOW" || \
  fail 'session job must use the full GitHub-hosted six-hour limit'

grep -Fq 'run: sleep infinity' "$WORKFLOW" || \
  fail 'session must wait for platform termination instead of exiting early'

grep -Fq 'inputs.target_repo' "$WORKFLOW" && \
  fail 'real repository names must not come from public workflow inputs'

if sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$ALLOWLIST" | grep -Fq '/'; then
  fail 'public allowlist must not contain owner/repository names'
fi

grep -Fq 'pull_request_target' "$WORKFLOW" && \
  fail 'workflow must not use pull_request_target'

grep -Fq '/.github/ @ronhuafeng' "$CODEOWNERS" || \
  fail 'security-sensitive GitHub configuration lacks an explicit code owner'
grep -Fq '/SECURITY.md @ronhuafeng' "$CODEOWNERS" || \
  fail 'security policy lacks an explicit code owner'

grep -Fq 'openssh-server' "$CONNECT_SCRIPT" || \
  fail 'fallback mode must install the SSH server explicitly'

grep -Fq 'ListenAddress %s' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must bind only to the Tailscale address'

grep -Fq 'AddressFamily inet6' "$CONNECT_SCRIPT" || \
  fail 'fallback SSH must use the IPv6-only tailnet path'

if grep -Fq 'tailnet_ipv4' "$CONNECT_SCRIPT"; then
  fail 'fallback SSH must not depend on conflicting CGNAT routes'
fi

grep -Fq '/health' "$CONNECT_SCRIPT" || \
  fail 'Headscale health must be checked before classifying registration errors'

grep -Fq 'sudo install -d -m 0755 /var/run/tailscale' "$CONNECT_SCRIPT" || \
  fail 'direct tailscaled startup must create its socket directory'

if grep -Eq 'tailscaled([[:space:]\\]|$)' "$CONNECT_SCRIPT" && \
   grep -Eq '&[[:space:]]+then' "$CONNECT_SCRIPT"; then
  fail 'background daemon startup must not use an asynchronous if condition'
fi

grep -Fq 'tailscale status --json' "$CONNECT_SCRIPT" || \
  fail 'daemon readiness must work before the node is logged in'

grep -Fq -- '--accept-dns=false' "$CONNECT_SCRIPT" || \
  fail 'runner must not install tailnet DNS settings'

if grep -Eq 'HEADSCALE_MAGIC_DNS_DOMAIN|DNSName|runner-fqdn' "$CONNECT_SCRIPT"; then
  fail 'runner connection must not validate or persist MagicDNS names'
fi

grep -Fq 'enable_devspace:' "$WORKFLOW" || \
  fail 'DevSpace must remain an explicit workflow opt-in'
if grep -Fq 'runs-on: ubuntu-latest' "$WORKFLOW"; then
  fail 'runner image must use the explicit Ubuntu 24.04 label'
fi
[[ "$(grep -Fc 'runs-on: ubuntu-24.04' "$WORKFLOW")" -eq 2 ]] || \
  fail 'both jobs must use Ubuntu 24.04'
grep -Fq 'actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020' "$WORKFLOW" || \
  fail 'session Node runtime action is not pinned'
grep -Fq 'node-version: 22.22.2' "$WORKFLOW" || \
  fail 'session Node runtime version is not fixed'
grep -Fq 'run: bash scripts/setup-development-environment.sh' "$WORKFLOW" || \
  fail 'development environment is not installed for runner sessions'
grep -Fq 'run: npm install -g @openai/codex@latest' "$WORKFLOW" || \
  fail 'Codex CLI must explicitly track npm latest'
grep -Fq 'run: npm install -g @anthropic-ai/claude-code@latest' "$WORKFLOW" || \
  fail 'Claude Code must explicitly track npm latest'
grep -Fq 'run: bash scripts/verify-development-environment.sh' "$WORKFLOW" || \
  fail 'development environment is not verified before network setup'

require_unconditional_step 'Prepare Node runtime' 'Install development environment' \
  'Node runtime preparation'
require_unconditional_step 'Install development environment' 'Install Codex CLI' \
  'development environment installation'
require_unconditional_step 'Install Codex CLI' 'Install Claude Code' \
  'Codex CLI installation'
require_unconditional_step 'Install Claude Code' 'Verify development environment' \
  'Claude Code installation'
require_unconditional_step 'Verify development environment' 'Prepare network' \
  'development environment verification'

# shellcheck source=../scripts/development-versions.env
source "$DEVELOPMENT_VERSIONS"
[[ "$NODE_VERSION" == '22.22.2' ]] || fail 'Node version is not pinned'
[[ "$COREPACK_VERSION" == '0.35.0' ]] || fail 'Corepack version is not pinned'
[[ "$PNPM_VERSION" == '11.4.0' ]] || fail 'pnpm version is not pinned'
[[ "$YARN_VERSION" == '4.17.1' ]] || fail 'Yarn version is not pinned'
[[ "$UV_VERSION" == '0.11.16' ]] || fail 'uv version is not pinned'
[[ "$MISE_VERSION" == 'v2026.7.0' ]] || fail 'mise version is not pinned'
[[ "$PYTHON_VERSION" == '3.14.6' ]] || fail 'Python version is not pinned'
[[ "$GO_VERSION" == '1.26.5' ]] || fail 'Go version is not pinned'
[[ "$RUST_VERSION" == '1.97.1' ]] || fail 'Rust version is not pinned'
[[ "$TERRAFORM_VERSION" == '1.15.5' ]] || fail 'Terraform version is not pinned'
[[ "$OPENTOFU_VERSION" == '1.11.7' ]] || fail 'OpenTofu version is not pinned'
[[ "$PLAYWRIGHT_VERSION" == '1.60.0' ]] || fail 'Playwright version is not pinned'
[[ "$MIGRATE_VERSION" == '4.19.1' ]] || fail 'database migration tool version is not pinned'
if grep -Eq 'CODEX|CLAUDE|@openai/codex|@anthropic-ai/claude-code' "$DEVELOPMENT_VERSIONS"; then
  fail 'Codex and Claude must not be pinned in the development version manifest'
fi

for package in bat direnv fd-find fzf htop lsof ripgrep socat tmux tree; do
  grep -Eq "^[[:space:]]+${package}([[:space:]]*\\\\)?$" "$DEVELOPMENT_SETUP" || \
    fail "$package is missing from the base development tools"
done

grep -Fq '/usr/bin/fdfind /usr/local/bin/fd' "$DEVELOPMENT_SETUP" || \
  fail 'fd compatibility command is missing'
grep -Fq '/usr/bin/batcat /usr/local/bin/bat' "$DEVELOPMENT_SETUP" || \
  fail 'bat compatibility command is missing'
grep -Fq 'direnv hook bash' "$DEVELOPMENT_SETUP" || \
  fail 'direnv is not enabled for SSH Bash sessions'
grep -Fq 'releases/download/${UV_VERSION}/uv-installer.sh' "$DEVELOPMENT_SETUP" || \
  fail 'uv installer URL is not versioned'
grep -Fq 'jdx/mise/releases/download/${MISE_VERSION}/install.sh' "$DEVELOPMENT_SETUP" || \
  fail 'mise installer URL is not versioned'
grep -Fq 'corepack@${COREPACK_VERSION}' "$DEVELOPMENT_SETUP" || \
  fail 'Corepack version is not applied'
grep -Fq 'pnpm@${PNPM_VERSION}' "$DEVELOPMENT_SETUP" || \
  fail 'pnpm version is not applied'
grep -Fq 'yarn@${YARN_VERSION}' "$DEVELOPMENT_SETUP" || \
  fail 'Yarn version is not applied'
for tool in python go rust terraform opentofu; do
  grep -Fq "$tool = \"\${${tool^^}_VERSION}\"" "$DEVELOPMENT_SETUP" 2>/dev/null || true
done
grep -Fq 'python = "${PYTHON_VERSION}"' "$DEVELOPMENT_SETUP" || \
  fail 'Python version is not managed by mise'
grep -Fq 'go = "${GO_VERSION}"' "$DEVELOPMENT_SETUP" || \
  fail 'Go version is not managed by mise'
grep -Fq 'rust = "${RUST_VERSION}"' "$DEVELOPMENT_SETUP" || \
  fail 'Rust version is not managed by mise'
grep -Fq 'terraform = "${TERRAFORM_VERSION}"' "$DEVELOPMENT_SETUP" || \
  fail 'Terraform version is not managed by mise'
grep -Fq 'opentofu = "${OPENTOFU_VERSION}"' "$DEVELOPMENT_SETUP" || \
  fail 'OpenTofu version is not managed by mise'
grep -Fq '@playwright/test@${PLAYWRIGHT_VERSION}' "$DEVELOPMENT_SETUP" || \
  fail 'Playwright version is not applied'
grep -Fq 'playwright install --with-deps chromium' "$DEVELOPMENT_SETUP" || \
  fail 'Playwright Chromium is not installed'
grep -Fq 'golang-migrate/migrate/v4/cmd/migrate@v${MIGRATE_VERSION}' "$DEVELOPMENT_SETUP" || \
  fail 'database migration CLI is not installed at a pinned version'
grep -Fq 'sha256sum --check --status' "$DEVELOPMENT_SETUP" || \
  fail 'downloaded Kubernetes plugins are not checksum verified'
for plugin in kubectl-ctx kubectl-ns kubectl-neat; do
  grep -Fq "/usr/local/bin/$plugin" "$DEVELOPMENT_SETUP" || \
    fail "$plugin is not installed"
done

grep -Fq 'runner-bootstrap' "$DEVELOPMENT_SETUP" || \
  fail 'project bootstrap helper is not installed'
if grep -Fq 'bootstrap-project.sh' "$WORKFLOW"; then
  fail 'project dependency installation must remain an explicit operator action'
fi
for command in 'mise install' 'corepack pnpm install --frozen-lockfile' \
  'corepack yarn install --immutable' 'npm ci' 'uv sync --frozen' \
  'go mod download' 'cargo fetch --locked' 'playwright install --with-deps chromium'; do
  grep -Fq "$command" "$PROJECT_BOOTSTRAP" || \
    fail "project bootstrap is missing: $command"
done

grep -Fq 'codex --version' "$DEVELOPMENT_VERIFY" || \
  fail 'Codex installation is not verified'
grep -Fq 'claude --version' "$DEVELOPMENT_VERIFY" || \
  fail 'Claude installation is not verified'
grep -Fq 'persist_node_commands' "$DEVELOPMENT_VERIFY" || \
  fail 'Node-installed commands are not persisted for SSH sessions'
grep -Fq 'go version -m' "$DEVELOPMENT_VERIFY" || \
  fail 'database migration CLI module version is not verified'
grep -Fq 'kubectl plugin list' "$DEVELOPMENT_VERIFY" || \
  fail 'Kubernetes plugins are not verified'

for script in "$DEVELOPMENT_SETUP" "$DEVELOPMENT_VERIFY" "$PROJECT_BOOTSTRAP"; do
  bash -n "$script" || fail "shell syntax check failed: $script"
  if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$script"; then
    fail "development script can expose secrets: $script"
  fi
done

grep -Fq 'bash scripts/install-cloudflared.sh' "$WORKFLOW" || \
  fail 'workflow does not install the pinned tunnel binary'
grep -Fq 'bash scripts/start-devspace.sh' "$WORKFLOW" || \
  fail 'workflow does not start DevSpace'

if grep -Eq 'GITHUB_OUTPUT.*(MCP|DEVSPACE|OWNER|PUBLIC)' "$WORKFLOW"; then
  fail 'DevSpace connection material must not use workflow outputs'
fi

grep -Fq "version='2026.7.2'" "$CLOUDFLARED_SCRIPT" || \
  fail 'cloudflared version is not pinned'
grep -Fq "sha256='ec905ea7b7e327ff8abdde8cb64697a2152de74dbcdbf6aec9db8364eb3886cd'" \
  "$CLOUDFLARED_SCRIPT" || fail 'cloudflared checksum is not pinned'
grep -Fq 'sha256sum --check --status' "$CLOUDFLARED_SCRIPT" || \
  fail 'cloudflared download is not checksum verified'

grep -Fq "devspace_package='@waishnav/devspace@1.0.4'" "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace package version is not pinned'
grep -Fq 'DEVSPACE_ALLOWED_ROOTS="$workspace"' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace filesystem scope is not restricted to the cloned workspace'
grep -Fq 'DEVSPACE_SUBAGENTS=0' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace subagents must be disabled by default'
grep -Fq 'connection.txt' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace connection material is not written locally'
grep -Fq 'chmod 0600' "$DEVSPACE_SCRIPT" || \
  fail 'DevSpace connection material does not receive private permissions'

if grep -Eq '(^|[[:space:]])(set -x|printenv)([[:space:]]|$)' "$DEVSPACE_SCRIPT"; then
  fail 'DevSpace launcher contains a command that can expose secrets'
fi

grep -Fq 'devspace.pid' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not terminate DevSpace'
grep -Fq 'cloudflared.pid' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not terminate cloudflared'
grep -Fq 'private-runner-session/devspace' "$CLEANUP_SCRIPT" || \
  fail 'cleanup does not remove local connection material'

printf 'workflow security tests passed\n'
