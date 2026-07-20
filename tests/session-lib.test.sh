#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT_DIR/scripts/session-lib.sh"
FIXTURE="$ROOT_DIR/tests/fixtures/target-repositories.txt"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_exit() {
  local expected="$1"
  shift

  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e

  [[ "$actual" -eq "$expected" ]] || fail "expected exit $expected, got $actual: $*"
}

assert_eq \
  'repo--alice--private-api' \
  "$(bash "$LIB" resolve-target 'alice/private-api' "$FIXTURE")" \
  'supported repository resolves to its environment'

assert_eq \
  'repo--none' \
  "$(bash "$LIB" resolve-target '' "$FIXTURE")" \
  'empty repository resolves to the credential-free environment'

assert_exit 10 bash "$LIB" resolve-target 'mallory/unknown' "$FIXTURE"
assert_exit 10 bash "$LIB" resolve-target '../bad/repo' "$FIXTURE"

key_dir="$(mktemp -d)"
trap 'rm -rf "$key_dir"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$key_dir/id_ed25519"

bash "$LIB" validate-key "$(<"$key_dir/id_ed25519.pub")"
bash "$LIB" validate-key \
  'sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fAAAABHNzaDo= operator@example'
assert_exit 30 bash "$LIB" validate-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey operator@example'
assert_exit 30 bash "$LIB" validate-key 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ'
assert_exit 30 bash "$LIB" validate-key $'ssh-ed25519 AAAA\ninjected'

printf 'session-lib tests passed\n'
