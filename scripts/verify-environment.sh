#!/usr/bin/env bash

set -euo pipefail

environment_name="${1-}"
repository="${GITHUB_REPOSITORY-}"
api_url="${GITHUB_API_URL-https://api.github.com}"
token="${GITHUB_TOKEN-}"
diagnostic_dir="${RUNNER_TEMP:-/tmp}"

[[ "$environment_name" =~ ^repo--[A-Za-z0-9._-]+(--[A-Za-z0-9._-]+)?$ ]] || {
  printf 'E11\n' >&2
  exit 11
}
[[ "$repository" =~ ^[^/]+/[^/]+$ ]] || {
  printf 'E11\n' >&2
  exit 11
}

response_file="$diagnostic_dir/environment-response.json"
status="$({
  curl --silent --show-error --location \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --header 'Accept: application/vnd.github+json' \
    --header "Authorization: Bearer $token" \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    "$api_url/repos/$repository/environments/$environment_name"
} 2>"$diagnostic_dir/environment-request.log")" || status=000

if [[ "$status" != 200 ]]; then
  printf 'E11\n' >&2
  exit 11
fi
