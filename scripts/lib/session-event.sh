#!/usr/bin/env bash

# Shared normalized session-event model. This file is sourced by controlled
# repository scripts; it must not print event data or credentials by itself.

session_event_now_epoch() {
  local value="${SESSION_EVENT_NOW_EPOCH-}"
  if [[ -n "$value" ]]; then
    [[ "$value" =~ ^[0-9]{10}$ ]] || return 1
    printf '%s\n' "$value"
    return 0
  fi
  date -u +%s
}

session_event_iso8601() {
  local epoch="$1"
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
}

session_event_validate_event() {
  case "$1" in
    starting|ssh-online|setup-ready|setup-degraded|service-online|offline)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

session_event_validate_service() {
  case "$1" in
    devspace|t3code)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

session_event_read_private_line() {
  local path="$1"
  local value=''
  [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
  [[ "$(stat -c '%a' "$path")" =~ ^(400|600)$ ]] || return 1
  [[ "$(wc -l < "$path")" -eq 1 ]] || return 1
  IFS= read -r value < "$path" || return 1
  [[ -n "$value" && "$value" != *$'\r'* ]] || return 1
  printf '%s\n' "$value"
}

session_event_service_url() {
  local service="$1"
  local home_dir="${HOME:?HOME is required}"
  local path=''
  local value=''

  case "$service" in
    devspace)
      path="$home_dir/private-runner-session/devspace/mcp-url"
      ;;
    t3code)
      path="$home_dir/private-runner-session/t3code/t3-url"
      ;;
    *)
      return 1
      ;;
  esac

  value="$(session_event_read_private_line "$path")" || return 1
  [[ "$value" =~ ^https://[^[:space:]]+$ ]] || return 1
  printf '%s\n' "$value"
}

session_event_setup_status() {
  local event="$1"
  local status_file="${HOME:?HOME is required}/private-runner-session/setup-status"
  local value=''

  case "$event" in
    starting|ssh-online)
      printf 'installing\n'
      ;;
    setup-ready)
      printf 'ready\n'
      ;;
    setup-degraded)
      printf 'degraded\n'
      ;;
    offline)
      printf 'offline\n'
      ;;
    service-online)
      if value="$(session_event_read_private_line "$status_file" 2>/dev/null)"; then
        case "$value" in
          installing|ready|degraded)
            printf '%s\n' "$value"
            return 0
            ;;
        esac
      fi
      printf 'ready\n'
      ;;
    *)
      return 1
      ;;
  esac
}

session_event_expiry_epoch() {
  local now_epoch="$1"
  local state_dir="${HOME:?HOME is required}/private-runner-session"
  local expiry_file="$state_dir/lark-session-expiry"
  local expiry=''

  install -d -m 0700 "$state_dir" || return 1
  if [[ -f "$expiry_file" ]]; then
    expiry="$(session_event_read_private_line "$expiry_file")" || return 1
    [[ "$expiry" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$expiry"
    return 0
  fi

  expiry=$((now_epoch + 21600))
  umask 077
  printf '%s\n' "$expiry" > "$expiry_file" || return 1
  chmod 0600 "$expiry_file" || return 1
  printf '%s\n' "$expiry"
}

session_event_build() {
  local event="$1"
  local now_epoch=''
  local expiry_epoch=''
  local target_id="${SESSION_TARGET_ID-none}"
  local service="${SESSION_SERVICE-}"
  local repository="${GITHUB_REPOSITORY-}"
  local server_url="${GITHUB_SERVER_URL-https://github.com}"

  session_event_validate_event "$event" || return 64
  [[ "$target_id" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || return 65
  [[ "${GITHUB_RUN_ID-}" =~ ^[0-9]+$ ]] || return 65
  [[ "${GITHUB_RUN_ATTEMPT-}" =~ ^[0-9]+$ ]] || return 65
  [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 65
  [[ "$server_url" =~ ^https://[^[:space:]]+$ ]] || return 65

  now_epoch="$(session_event_now_epoch)" || return 65
  expiry_epoch="$(session_event_expiry_epoch "$now_epoch")" || return 65

  SE_EVENT="$event"
  SE_SESSION_KEY="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  SE_TARGET_ID="$target_id"
  SE_GITHUB_RUN_ID="$GITHUB_RUN_ID"
  SE_GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT"
  SE_ACTIONS_URL="${server_url}/${repository}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}"
  SE_SETUP_STATUS="$(session_event_setup_status "$event")" || return 65
  SE_SSH_ONLINE=false
  SE_SERVICE=''
  SE_SERVICE_ONLINE=false
  SE_SERVICE_URL=''
  SE_RUNNER_NAME="${SESSION_RUNNER_NAME-}"
  SE_OCCURRED_AT="$(session_event_iso8601 "$now_epoch")" || return 65
  SE_EXPIRES_AT="$(session_event_iso8601 "$expiry_epoch")" || return 65
  SE_ERROR_CODE="${SESSION_ERROR_CODE-}"

  case "$event" in
    ssh-online|setup-ready|setup-degraded|service-online)
      if [[ "${SESSION_SSH_ONLINE-false}" == true ]]; then
        SE_SSH_ONLINE=true
      fi
      ;;
  esac

  if [[ "$event" == service-online ]]; then
    session_event_validate_service "$service" || return 64
    SE_SERVICE="$service"
    SE_SERVICE_ONLINE=true
    SE_SERVICE_URL="$(session_event_service_url "$service")" || return 66
  fi

  [[ "$SE_RUNNER_NAME" != *$'\n'* && "$SE_RUNNER_NAME" != *$'\r'* ]] || return 65
  [[ "$SE_ERROR_CODE" =~ ^[A-Za-z0-9._-]{0,32}$ ]] || return 65
}

session_event_to_json() {
  python3 - <<'PY'
import json
import os

fields = {
    "event": os.environ["SE_EVENT"],
    "session_key": os.environ["SE_SESSION_KEY"],
    "target_id": os.environ["SE_TARGET_ID"],
    "github_run_id": os.environ["SE_GITHUB_RUN_ID"],
    "github_run_attempt": os.environ["SE_GITHUB_RUN_ATTEMPT"],
    "actions_url": os.environ["SE_ACTIONS_URL"],
    "setup_status": os.environ["SE_SETUP_STATUS"],
    "ssh_online": os.environ["SE_SSH_ONLINE"] == "true",
    "service": os.environ["SE_SERVICE"],
    "service_online": os.environ["SE_SERVICE_ONLINE"] == "true",
    "service_url": os.environ["SE_SERVICE_URL"],
    "runner_name": os.environ["SE_RUNNER_NAME"],
    "occurred_at": os.environ["SE_OCCURRED_AT"],
    "expires_at": os.environ["SE_EXPIRES_AT"],
    "error_code": os.environ["SE_ERROR_CODE"],
}
print(json.dumps(fields, separators=(",", ":"), sort_keys=True))
PY
}

session_event_export() {
  export SE_EVENT SE_SESSION_KEY SE_TARGET_ID SE_GITHUB_RUN_ID
  export SE_GITHUB_RUN_ATTEMPT SE_ACTIONS_URL SE_SETUP_STATUS SE_SSH_ONLINE
  export SE_SERVICE SE_SERVICE_ONLINE SE_SERVICE_URL SE_RUNNER_NAME
  export SE_OCCURRED_AT SE_EXPIRES_AT SE_ERROR_CODE
}
