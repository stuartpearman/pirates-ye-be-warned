#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

configure_jellyfin() {
  wait_for_http Jellyfin "$JELLYFIN_URL/System/Info/Public" 60

  local payload_file
  local status
  local attempt

  for ((attempt = 1; attempt <= 90; attempt++)); do
    status="$(curl -sS -o /dev/null -w '%{http_code}' "$JELLYFIN_URL/Startup/User" || true)"

    if [[ "$status" == "200" ]]; then
      break
    fi

    if [[ "$status" == "401" || "$status" == "403" || "$status" == "404" ]]; then
      echo "Skipping Jellyfin; startup wizard is already completed or user setup is locked" >&2
      return 0
    fi

    sleep 2
  done

  if [[ "$status" != "200" ]]; then
    echo "Jellyfin startup user endpoint did not become ready; last HTTP status was $status" >&2
    return 1
  fi

  payload_file="$(mktemp)"

  python3 - "$payload_file" "$SERVICE_USERNAME" "$SERVICE_PASSWORD" <<'PY'
import json
import sys

destination, username, password = sys.argv[1:4]
with open(destination, "w", encoding="utf-8") as file:
    json.dump({"Name": username, "Password": password}, file)
PY

  for ((attempt = 1; attempt <= 30; attempt++)); do
    status="$(curl -sS -o /dev/null -w '%{http_code}' \
      -H "Content-Type: application/json" \
      --data-binary "@$payload_file" \
      "$JELLYFIN_URL/Startup/User" || true)"

    if [[ "$status" != "500" ]]; then
      break
    fi

    sleep 2
  done

  rm -f "$payload_file"

  if [[ "$status" == "200" || "$status" == "204" ]]; then
    curl -fsS -X POST "$JELLYFIN_URL/Startup/Complete" >/dev/null || true
    echo "Configured Jellyfin startup user"
    return 0
  fi

  if [[ "$status" == "401" || "$status" == "403" || "$status" == "404" ]]; then
    echo "Skipping Jellyfin; startup wizard is already completed or user setup is locked" >&2
    return 0
  fi

  echo "Jellyfin startup user request returned HTTP $status" >&2
  return 1
}

main() {
  load_env
  init_common_env
  require_command curl
  require_command python3
  require_env_vars SERVICE_USERNAME SERVICE_PASSWORD
  configure_jellyfin
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi