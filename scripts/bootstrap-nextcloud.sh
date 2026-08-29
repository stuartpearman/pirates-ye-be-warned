#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/domain.sh
source "$SCRIPT_DIR/lib/domain.sh"

configure_nextcloud() {
  local mounts_file
  local attempt

  wait_for_http Nextcloud "$NEXTCLOUD_URL/status.php" 120

  for ((attempt = 1; attempt <= 120; attempt++)); do
    if compose exec -T -u www-data nextcloud php occ status --output=json | grep -q '"installed":true'; then
      break
    fi
    sleep 2
  done

  if ! compose exec -T -u www-data nextcloud php occ status --output=json | grep -q '"installed":true'; then
    echo "Nextcloud did not finish initial installation" >&2
    return 1
  fi

  compose exec -T -u www-data nextcloud php occ app:enable files_external >/dev/null

  compose exec -T -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="$(fqdn "$NEXTCLOUD_SUBDOMAIN")" >/dev/null
  compose exec -T -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="http://$(fqdn "$NEXTCLOUD_SUBDOMAIN")" >/dev/null
  compose exec -T -u www-data nextcloud php occ config:system:set overwriteprotocol --value=http >/dev/null

  mounts_file="$(mktemp)"
  compose exec -T -u www-data nextcloud php occ files_external:list "$SERVICE_USERNAME" --output=json > "$mounts_file"

  if python3 - "$mounts_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as file:
    mounts = json.load(file)

for mount in mounts:
    if mount.get("mount_point") == "/Shared" and mount.get("configuration", {}).get("datadir") == "/shared":
        sys.exit(0)

sys.exit(1)
PY
  then
    rm -f "$mounts_file"
    echo "Nextcloud Shared external storage already exists"
    return 0
  fi

  rm -f "$mounts_file"

  compose exec -T -u www-data nextcloud php occ files_external:create \
    /Shared local null::null \
    --user "$SERVICE_USERNAME" \
    -c datadir=/shared >/dev/null

  compose exec -T -u www-data nextcloud php occ files:scan --path="$SERVICE_USERNAME/files/Shared" >/dev/null

  echo "Configured Nextcloud Shared external storage"
}

main() {
  load_env
  init_common_env
  init_domain_env
  require_command curl
  require_command docker
  require_command python3
  require_env_vars SERVICE_USERNAME SERVICE_PASSWORD
  configure_nextcloud
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi