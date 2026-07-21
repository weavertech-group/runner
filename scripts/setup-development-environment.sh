#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=development-versions.env
source "$ROOT_DIR/scripts/development-versions.env"

runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
diagnostic_dir="$runner_temp/private-runner-diagnostics"
log_file="$diagnostic_dir/development-environment.log"
temporary_dir="$runner_temp/private-runner-development"
local_bin="${HOME:?HOME is required}/.local/bin"
mise_config="$HOME/.config/mise/config.toml"
kubernetes_cache_dir="$HOME/.cache/private-runner/kubernetes"
development_cache_hit="${DEVELOPMENT_CACHE_HIT:-false}"

fail() {
  printf 'E55\n' >&2
  exit 55
}

install_uv() {
  local uv_archive="$temporary_dir/uv.tar.gz"
  local uv_dir="$temporary_dir/uv"

  curl --fail --silent --show-error --location --retry 3 \
    --proto '=https' --tlsv1.2 \
    --output "$uv_archive" \
    "https://releases.astral.sh/github/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz"
  printf '%s  %s\n' "$UV_SHA256" "$uv_archive" | \
    sha256sum --check --status
  mkdir -p "$uv_dir"
  tar -xzf "$uv_archive" --strip-components=1 -C "$uv_dir"
  install -m 0755 "$uv_dir/uv" "$local_bin/uv"
  install -m 0755 "$uv_dir/uvx" "$local_bin/uvx"
}

install_mise() {
  curl --fail --silent --show-error --location --retry 3 \
    --proto '=https' --tlsv1.2 \
    --output "$temporary_dir/mise-installer.sh" \
    "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/install.sh"
  MISE_VERSION="$MISE_VERSION" \
    MISE_INSTALL_PATH="$local_bin/mise" \
    MISE_QUIET=1 \
    sh "$temporary_dir/mise-installer.sh"
}

mise_cache_ready() {
  [[ "$development_cache_hit" == true && -x "$local_bin/mise" ]] || return 1

  local tool=''
  for tool in \
    "python@${PYTHON_VERSION}" \
    "go@${GO_VERSION}" \
    "rust@${RUST_VERSION}" \
    "terraform@${TERRAFORM_VERSION}" \
    "opentofu@${OPENTOFU_VERSION}"; do
    "$local_bin/mise" where "$tool" >/dev/null 2>&1 || return 1
  done
}

browser_cache_ready() {
  [[ "$development_cache_hit" == true ]] || return 1
  find "$HOME/.cache/ms-playwright" -maxdepth 1 -type d \
    \( -name 'chromium-*' -o -name 'chromium_headless_shell-*' -o -name 'chrome-*' \) \
    -print -quit 2>/dev/null | grep -q .
}

install_kubernetes_plugins() {
  local kubectx_archive="$kubernetes_cache_dir/kubectx-${KUBECTX_VERSION}.tar.gz"
  local kubectx_dir="$temporary_dir/kubectx"
  local neat_archive="$kubernetes_cache_dir/kubectl-neat-${KUBECTL_NEAT_VERSION}.tar.gz"
  local neat_dir="$temporary_dir/kubectl-neat"

  install -d -m 0700 "$kubernetes_cache_dir"

  if [[ ! -f "$kubectx_archive" ]]; then
    curl --fail --silent --show-error --location --retry 3 \
      --proto '=https' --tlsv1.2 \
      --output "$kubectx_archive" \
      "https://github.com/ahmetb/kubectx/archive/v${KUBECTX_VERSION}.tar.gz"
  fi
  printf '%s  %s\n' "$KUBECTX_SHA256" "$kubectx_archive" | \
    sha256sum --check --status
  mkdir -p "$kubectx_dir"
  tar -xzf "$kubectx_archive" --strip-components=1 -C "$kubectx_dir"
  sudo install -m 0755 "$kubectx_dir/kubectx" /usr/local/bin/kubectx
  sudo install -m 0755 "$kubectx_dir/kubens" /usr/local/bin/kubens
  sudo ln -sfn /usr/local/bin/kubectx /usr/local/bin/kubectl-ctx
  sudo ln -sfn /usr/local/bin/kubens /usr/local/bin/kubectl-ns

  if [[ ! -f "$neat_archive" ]]; then
    curl --fail --silent --show-error --location --retry 3 \
      --proto '=https' --tlsv1.2 \
      --output "$neat_archive" \
      "https://github.com/itaysk/kubectl-neat/releases/download/v${KUBECTL_NEAT_VERSION}/kubectl-neat_linux_amd64.tar.gz"
  fi
  printf '%s  %s\n' "$KUBECTL_NEAT_SHA256" "$neat_archive" | \
    sha256sum --check --status
  mkdir -p "$neat_dir"
  tar -xzf "$neat_archive" -C "$neat_dir"
  sudo install -m 0755 "$neat_dir/kubectl-neat" /usr/local/bin/kubectl-neat
}

configure_shell() {
  local profile_marker='# private-runner development environment'
  local bashrc_marker='# private-runner direnv hook'

  if ! grep -Fq "$profile_marker" "$HOME/.profile" 2>/dev/null; then
    cat >> "$HOME/.profile" <<'EOF'

# private-runner development environment
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/go/bin:$PATH"
EOF
  fi

  if ! grep -Fq "$bashrc_marker" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'EOF'

# private-runner direnv hook
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
EOF
  fi

  if [[ -n "${GITHUB_PATH-}" ]]; then
    printf '%s\n' \
      "$HOME/.local/bin" \
      "$HOME/.local/share/mise/shims" \
      "$HOME/go/bin" >> "$GITHUB_PATH"
  fi
}

main() {
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]]
  grep -Fq 'VERSION_ID="24.04"' /etc/os-release

  sudo apt-get update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    bat \
    build-essential \
    ca-certificates \
    curl \
    direnv \
    fd-find \
    fzf \
    git \
    htop \
    jq \
    libbz2-dev \
    libffi-dev \
    libgdbm-dev \
    liblzma-dev \
    libncurses-dev \
    libnss3-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    lsof \
    pkg-config \
    ripgrep \
    socat \
    tk-dev \
    tmux \
    tree \
    unzip \
    uuid-dev \
    xz-utils \
    zlib1g-dev

  sudo ln -sfn /usr/bin/fdfind /usr/local/bin/fd
  sudo ln -sfn /usr/bin/batcat /usr/local/bin/bat

  install -d -m 0700 \
    "$local_bin" \
    "$temporary_dir" \
    "$HOME/.config/mise" \
    "$kubernetes_cache_dir"
  if [[ "$development_cache_hit" != true || ! -x "$local_bin/uv" || ! -x "$local_bin/uvx" ]]; then
    install_uv
  fi
  if [[ "$development_cache_hit" != true || ! -x "$local_bin/mise" ]]; then
    install_mise
  fi

  export PATH="$local_bin:$HOME/.local/share/mise/shims:$HOME/go/bin:$PATH"

  npm install --global --no-audit --no-fund "corepack@${COREPACK_VERSION}"
  corepack enable
  corepack install --global "pnpm@${PNPM_VERSION}"
  corepack install --global "yarn@${YARN_VERSION}"

  cat > "$mise_config" <<EOF
[tools]
python = "${PYTHON_VERSION}"
go = "${GO_VERSION}"
rust = "${RUST_VERSION}"
terraform = "${TERRAFORM_VERSION}"
opentofu = "${OPENTOFU_VERSION}"
EOF
  chmod 0600 "$mise_config"

  if ! mise_cache_ready; then
    MISE_YES=1 \
      MISE_JOBS=2 \
      MISE_GITHUB_ATTESTATIONS=true \
      MISE_AQUA_GITHUB_ATTESTATIONS=true \
      MISE_PYTHON_GITHUB_ATTESTATIONS=true \
      mise install
  fi
  mise reshim

  npm install --global --no-audit --no-fund \
    "@playwright/test@${PLAYWRIGHT_VERSION}"
  if browser_cache_ready; then
    playwright install-deps chromium
  else
    playwright install --with-deps chromium
  fi

  if [[ "$development_cache_hit" != true || ! -x "$HOME/go/bin/migrate" ]]; then
    CGO_ENABLED=1 mise exec "go@${GO_VERSION}" -- \
      go install -tags 'postgres mysql sqlite3' \
      "github.com/golang-migrate/migrate/v4/cmd/migrate@v${MIGRATE_VERSION}"
  fi

  install_kubernetes_plugins
  install -m 0755 "$ROOT_DIR/scripts/bootstrap-project.sh" \
    "$local_bin/runner-bootstrap"
  configure_shell
}

install -d -m 0700 "$diagnostic_dir" "$temporary_dir" || fail
: > "$log_file" || fail
chmod 0600 "$log_file" || fail

if ! main >> "$log_file" 2>&1; then
  fail
fi

printf '%s\n' 'Development environment installed.'
