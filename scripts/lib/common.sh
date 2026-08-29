#!/usr/bin/env bash

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$SCRIPT_LIB_DIR/../.." && pwd)}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing .env file at $ENV_FILE" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key#${key%%[![:space:]]*}}"
    key="${key%${key##*[![:space:]]}}"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    export "$key=$value"
  done < "$ENV_FILE"
}

init_common_env() {
  SERVICE_USERNAME="${SERVICE_USERNAME:-}"
  SERVICE_PASSWORD="${SERVICE_PASSWORD:-}"

  QBITTORRENT_URL="${QBITTORRENT_URL:-http://localhost:8090}"
  LIDARR_URL="${LIDARR_URL:-http://localhost:8686}"
  PROWLARR_URL="${PROWLARR_URL:-http://localhost:9696}"
  JELLYFIN_URL="${JELLYFIN_URL:-http://localhost:8096}"
  NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://localhost:8081}"

  QBITTORRENT_CONFIG="${QBITTORRENT_CONFIG:-$ROOT_DIR/config/qbittorrent/qBittorrent/qBittorrent.conf}"
  LIDARR_CONFIG="${LIDARR_CONFIG:-$ROOT_DIR/config/lidarr/config.xml}"
  PROWLARR_CONFIG="${PROWLARR_CONFIG:-$ROOT_DIR/config/prowlarr/config.xml}"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env_vars() {
  local name

  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "Missing required .env value: $name" >&2
      exit 1
    fi
  done
}

compose() {
  (cd "$ROOT_DIR" && docker compose "$@")
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local attempts="${3:-60}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "$name did not become reachable at $url" >&2
  return 1
}

wait_for_file() {
  local name="$1"
  local path="$2"
  local attempts="${3:-60}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if [[ -f "$path" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "$name did not create $path" >&2
  return 1
}

read_xml_value() {
  python3 - "$1" "$2" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, tag = sys.argv[1:3]
root = ET.parse(path).getroot()
value = root.findtext(tag)
print(value or "")
PY
}