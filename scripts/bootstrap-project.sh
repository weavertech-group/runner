#!/usr/bin/env bash

set -euo pipefail

workspace="${1:-$PWD}"
[[ -d "$workspace" ]] || {
  printf 'workspace is not a directory: %s\n' "$workspace" >&2
  exit 2
}
workspace="$(cd "$workspace" && pwd)"
cd "$workspace"

configured=false

if [[ -f mise.toml || -f .mise.toml || -f .tool-versions ]]; then
  printf '%s\n' 'Installing project tool versions with mise...'
  mise install
  configured=true
fi

if [[ -f pnpm-lock.yaml ]]; then
  printf '%s\n' 'Installing Node.js dependencies with pnpm...'
  corepack pnpm install --frozen-lockfile
  configured=true
elif [[ -f yarn.lock ]]; then
  printf '%s\n' 'Installing Node.js dependencies with Yarn...'
  corepack yarn install --immutable
  configured=true
elif [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
  printf '%s\n' 'Installing Node.js dependencies with npm ci...'
  npm ci
  configured=true
elif [[ -f package.json ]]; then
  printf '%s\n' 'Installing Node.js dependencies with npm...'
  npm install
  configured=true
fi

if [[ -f uv.lock ]]; then
  printf '%s\n' 'Installing locked Python dependencies with uv...'
  uv sync --frozen
  configured=true
elif [[ -f pyproject.toml ]]; then
  printf '%s\n' 'Installing Python project dependencies with uv...'
  uv sync
  configured=true
elif [[ -f requirements.lock ]]; then
  printf '%s\n' 'Installing locked Python requirements with uv...'
  uv venv --allow-existing .venv
  uv pip sync --python .venv/bin/python requirements.lock
  configured=true
elif [[ -f requirements.txt ]]; then
  printf '%s\n' 'Installing Python requirements with uv...'
  uv venv --allow-existing .venv
  uv pip install --python .venv/bin/python --requirement requirements.txt
  configured=true
fi

if [[ -f go.mod ]]; then
  printf '%s\n' 'Downloading Go modules...'
  go mod download
  configured=true
fi

if [[ -f Cargo.toml ]]; then
  printf '%s\n' 'Fetching Rust crates...'
  if [[ -f Cargo.lock ]]; then
    cargo fetch --locked
  else
    cargo fetch
  fi
  configured=true
fi

if [[ -f package.json ]] && jq -e '
    ((.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {})) |
    has("@playwright/test") or has("playwright")
  ' package.json >/dev/null; then
  printf '%s\n' 'Installing the project-compatible Playwright Chromium build...'
  if [[ -f pnpm-lock.yaml ]]; then
    corepack pnpm exec playwright install --with-deps chromium
  elif [[ -f yarn.lock ]]; then
    corepack yarn exec playwright install --with-deps chromium
  else
    npx --no-install playwright install --with-deps chromium
  fi
  configured=true
fi

if [[ "$configured" == false ]]; then
  printf '%s\n' 'No supported project dependency manifests were found.'
fi
