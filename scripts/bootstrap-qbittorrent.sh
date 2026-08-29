#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

configure_qbittorrent() {
  echo "Configuring qBittorrent Web UI credentials in mounted config"

  wait_for_file qBittorrent "$QBITTORRENT_CONFIG" 60
  compose stop qbittorrent >/dev/null

  python3 - "$QBITTORRENT_CONFIG" "$SERVICE_USERNAME" "$SERVICE_PASSWORD" <<'PY'
import base64
import hashlib
import os
import sys

path, username, password = sys.argv[1:4]
salt = os.urandom(16)
password_hash = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 100000)
encoded = f'@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(password_hash).decode()})'

settings = {
    "WebUI\\Username": username,
    "WebUI\\Password_PBKDF2": f'"{encoded}"',
    "WebUI\\LocalHostAuth": "false",
}

with open(path, "r", encoding="utf-8") as file:
    lines = file.read().splitlines()

output = []
in_preferences = False
seen = set()
inserted = False

for line in lines:
    if line.startswith("[") and line.endswith("]"):
        if in_preferences and not inserted:
            for key, value in settings.items():
                if key not in seen:
                    output.append(f"{key}={value}")
            inserted = True
        in_preferences = line == "[Preferences]"

    if in_preferences and "=" in line:
        key = line.split("=", 1)[0]
        if key in settings:
            output.append(f"{key}={settings[key]}")
            seen.add(key)
            continue

    output.append(line)

if in_preferences and not inserted:
    for key, value in settings.items():
        if key not in seen:
            output.append(f"{key}={value}")

with open(path, "w", encoding="utf-8") as file:
    file.write("\n".join(output) + "\n")
PY

  compose up -d qbittorrent >/dev/null
}

main() {
  load_env
  init_common_env
  require_command docker
  require_command python3
  require_env_vars SERVICE_USERNAME SERVICE_PASSWORD
  configure_qbittorrent
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi