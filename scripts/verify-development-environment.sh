#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=development-versions.env
source "$ROOT_DIR/scripts/development-versions.env"

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
log_file="$diagnostic_dir/development-environment-versions.log"
local_bin="${HOME:?HOME is required}/.local/bin"
verify_ai_tools="${VERIFY_AI_TOOLS:-true}"

fail() {
  printf 'E55\n' >&2
  exit 55
}

require_command() {
  command -v "$1" >/dev/null 2>&1
}

require_version() {
  local expected="$1"
  shift
  "$@" 2>&1 | grep -Fq "$expected"
}

persist_node_commands() {
  local command_name=''
  local command_path=''
  local commands=(node npm npx corepack pnpm yarn playwright)

  if [[ "$verify_ai_tools" == true ]]; then
    commands+=(codex claude)
  fi

  install -d -m 0700 "$local_bin"
  for command_name in "${commands[@]}"; do
    command_path="$(command -v "$command_name")"
    ln -sfn "$command_path" "$local_bin/$command_name"
  done
}

main() {
  export PATH="$local_bin:$HOME/.local/share/mise/shims:$HOME/go/bin:$PATH"
  persist_node_commands

  grep -Fq 'VERSION_ID="24.04"' /etc/os-release

  local command_name=''
  local commands=(
    bat cargo corepack direnv fd fzf go htop kubectx kubens lsof
    migrate mise node npm npx playwright pnpm python rg rustc socat terraform
    tmux tofu tree uv yarn kubectl kubectl-ctx kubectl-ns kubectl-neat
    runner-bootstrap
  )
  if [[ "$verify_ai_tools" == true ]]; then
    commands+=(claude codex)
  fi
  for command_name in "${commands[@]}"; do
    require_command "$command_name"
  done

  require_version "v${NODE_VERSION}" node --version
  require_version "$COREPACK_VERSION" corepack --version
  require_version "$PNPM_VERSION" pnpm --version
  require_version "$YARN_VERSION" yarn --version
  require_version "$UV_VERSION" uv --version
  require_version "${MISE_VERSION#v}" mise --version
  require_version "$PYTHON_VERSION" python --version
  require_version "go${GO_VERSION}" go version
  require_version "$RUST_VERSION" rustc --version
  require_version "v${TERRAFORM_VERSION}" terraform version
  require_version "v${OPENTOFU_VERSION}" tofu version
  require_version "$PLAYWRIGHT_VERSION" playwright --version
  go version -m "$(command -v migrate)" | \
    grep -Fq "github.com/golang-migrate/migrate/v4 v${MIGRATE_VERSION}"

  kubectl plugin list

  find "$HOME/.cache/ms-playwright" -maxdepth 1 -type d \
    \( -name 'chromium-*' -o -name 'chromium_headless_shell-*' -o -name 'chrome-*' \) \
    -print -quit | grep -q .

  if [[ "$verify_ai_tools" == true ]]; then
    codex --version
    claude --version
  fi

  {
    printf 'node='; node --version
    printf 'corepack='; corepack --version
    printf 'pnpm='; pnpm --version
    printf 'yarn='; yarn --version
    printf 'uv='; uv --version
    printf 'mise='; mise --version
    printf 'python='; python --version
    printf 'go='; go version
    printf 'rust='; rustc --version
    printf 'terraform='; terraform version | head -n 1
    printf 'opentofu='; tofu version | head -n 1
    printf 'playwright='; playwright --version
    printf 'migrate='; migrate -version
    if [[ "$verify_ai_tools" == true ]]; then
      printf 'codex='; codex --version
      printf 'claude='; claude --version
    fi
  } > "$log_file"
  chmod 0600 "$log_file"
}

install -d -m 0700 "$diagnostic_dir" || fail
if ! main >/dev/null 2>&1; then
  fail
fi

printf '%s\n' 'Development environment verified.'
