#!/usr/bin/env bash

set -euo pipefail

die() {
  local code="$1"
  local status="$2"
  printf '%s\n' "$code" >&2
  exit "$status"
}

resolve_target() {
  local target_repo="${1-}"
  local allowlist="${2-}"
  local repository environment extra

  if [[ -z "$target_repo" ]]; then
    printf 'repo--none\n'
    return
  fi

  [[ "$target_repo" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9._-]{1,100}$ ]] || \
    die E10 10
  [[ -r "$allowlist" ]] || die E10 10

  while read -r repository environment extra; do
    [[ -z "${repository:-}" || "$repository" == \#* ]] && continue
    [[ -z "${extra:-}" && "$environment" =~ ^repo--[A-Za-z0-9._-]+--[A-Za-z0-9._-]+$ ]] || \
      die E10 10

    if [[ "$repository" == "$target_repo" ]]; then
      printf '%s\n' "$environment"
      return
    fi
  done < "$allowlist"

  die E10 10
}

validate_key() {
  local public_key="${1-}"

  [[ "$public_key" != *$'\n'* && "$public_key" != *$'\r'* ]] || die E30 30
  [[ "$public_key" =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh.com)[[:space:]][A-Za-z0-9+/]+={0,3}([[:space:]][^[:cntrl:]]+)?$ ]] || \
    die E30 30
}

main() {
  local command="${1-}"
  shift || true

  case "$command" in
    resolve-target)
      resolve_target "$@"
      ;;
    validate-key)
      validate_key "$@"
      ;;
    *)
      printf 'usage: %s {resolve-target|validate-key} ...\n' "$0" >&2
      exit 64
      ;;
  esac
}

main "$@"
