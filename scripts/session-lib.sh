#!/usr/bin/env bash

set -euo pipefail

die() {
  local code="$1"
  local status="$2"
  printf '%s\n' "$code" >&2
  exit "$status"
}

resolve_target() {
  local target_id="${1-}"
  local allowlist="${2-}"
  local allowed_id environment extra

  if [[ -z "$target_id" ]]; then
    printf 'session--none\n'
    return
  fi

  [[ "$target_id" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || \
    die E10 10
  [[ -r "$allowlist" ]] || die E10 10

  while read -r allowed_id environment extra; do
    [[ -z "${allowed_id:-}" || "$allowed_id" == \#* ]] && continue
    [[ -z "${extra:-}" && "$environment" =~ ^session--[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || \
      die E10 10

    if [[ "$allowed_id" == "$target_id" ]]; then
      printf '%s\n' "$environment"
      return
    fi
  done < "$allowlist"

  die E10 10
}

validate_key() {
  local public_key="${1-}"
  local key_file fingerprint key_type expected_type

  [[ "$public_key" != *$'\n'* && "$public_key" != *$'\r'* ]] || die E30 30
  [[ "$public_key" =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh.com)[[:space:]][A-Za-z0-9+/]+={0,3}([[:space:]][^[:cntrl:]]+)?$ ]] || \
    die E30 30

  key_type="${BASH_REMATCH[1]}"
  key_file="$(mktemp)"
  chmod 600 "$key_file"
  printf '%s\n' "$public_key" > "$key_file"

  if ! fingerprint="$(ssh-keygen -l -f "$key_file" 2>/dev/null)"; then
    rm -f "$key_file"
    die E30 30
  fi
  rm -f "$key_file"

  case "$key_type" in
    ssh-ed25519)
      expected_type='(ED25519)'
      ;;
    sk-ssh-ed25519@openssh.com)
      expected_type='(ED25519-SK)'
      ;;
  esac
  [[ "$fingerprint" == *"$expected_type" ]] || die E30 30
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
