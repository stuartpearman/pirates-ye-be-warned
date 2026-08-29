#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

configure_arr() {
  local name="$1"
  local url="$2"
  local config_path="$3"
  local api_key
  local payload_file
  local updated_payload_file

  wait_for_file "$name" "$config_path" 60

  api_key="$(read_xml_value "$config_path" ApiKey)"
  if [[ -z "$api_key" ]]; then
    echo "Skipping $name; no ApiKey found in $config_path" >&2
    return 1
  fi

  wait_for_http "$name" "$url/ping" 60

  payload_file="$(mktemp)"
  updated_payload_file="$(mktemp)"

  curl -fsS -H "X-Api-Key: $api_key" "$url/api/v1/config/host" > "$payload_file"

  python3 - "$payload_file" "$updated_payload_file" "$SERVICE_USERNAME" "$SERVICE_PASSWORD" <<'PY'
import json
import sys

source, destination, username, password = sys.argv[1:5]
with open(source, "r", encoding="utf-8") as file:
    payload = json.load(file)

payload["authenticationMethod"] = "forms"
payload["authenticationRequired"] = "enabled"
payload["username"] = username
payload["password"] = password
payload["passwordConfirmation"] = password

with open(destination, "w", encoding="utf-8") as file:
    json.dump(payload, file)
PY

  curl -fsS \
    -X PUT \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $api_key" \
    --data-binary "@$updated_payload_file" \
    "$url/api/v1/config/host" >/dev/null

  rm -f "$payload_file" "$updated_payload_file"

  echo "Configured $name credentials"
}

main() {
  load_env
  init_common_env
  require_command curl
  require_command python3
  require_env_vars SERVICE_USERNAME SERVICE_PASSWORD

  configure_arr Lidarr "$LIDARR_URL" "$LIDARR_CONFIG"
  configure_arr Prowlarr "$PROWLARR_URL" "$PROWLARR_CONFIG"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi