#!/usr/bin/env bash

set -euo pipefail

target_repo="${TARGET_REPO-}"
credential="${TARGET_REPO_AUTH-}"
credential_file="${RUNNER_TEMP:?RUNNER_TEMP is required}/target-repo-credential"

if [[ -z "$target_repo" || -z "$credential" ]]; then
  printf 'E12\n' >&2
  exit 12
fi
if [[ ! "$target_repo" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/[A-Za-z0-9._-]{1,100}$ ]]; then
  printf 'E12\n' >&2
  exit 12
fi

printf '::add-mask::%s\n' "$credential"
umask 077

git config --global credential.https://github.com.useHttpPath true
git config --global credential.helper "store --file=$credential_file"

printf 'protocol=https\nhost=github.com\npath=%s.git\nusername=x-access-token\npassword=%s\n\n' \
  "$target_repo" "$credential" | git credential approve

[[ -s "$credential_file" ]] || {
  printf 'E12\n' >&2
  exit 12
}
