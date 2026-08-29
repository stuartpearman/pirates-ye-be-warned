#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=common.sh
  source "$SCRIPT_LIB_DIR/common.sh"
fi

init_domain_env() {
  LOCAL_DOMAIN="${LOCAL_DOMAIN:-example-pi.local}"
  PI_LAN_IP="${PI_LAN_IP:-}"
  HOMEPAGE_SUBDOMAIN="${HOMEPAGE_SUBDOMAIN:-home}"
  LIDARR_SUBDOMAIN="${LIDARR_SUBDOMAIN:-lid}"
  PROWLARR_SUBDOMAIN="${PROWLARR_SUBDOMAIN:-prowl}"
  QBITTORRENT_SUBDOMAIN="${QBITTORRENT_SUBDOMAIN:-qb}"
  NEXTCLOUD_SUBDOMAIN="${NEXTCLOUD_SUBDOMAIN:-nextcloud}"
  JELLYFIN_SUBDOMAIN="${JELLYFIN_SUBDOMAIN:-jelly}"
  PLEX_SUBDOMAIN="${PLEX_SUBDOMAIN:-plex}"
}

detect_lan_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}'
}

fqdn() {
  printf '%s.%s' "$1" "$LOCAL_DOMAIN"
}

local_hostnames() {
  printf '%s\n' \
    "$LOCAL_DOMAIN" \
    "$(fqdn "$HOMEPAGE_SUBDOMAIN")" \
    "$(fqdn "$LIDARR_SUBDOMAIN")" \
    "$(fqdn "$PROWLARR_SUBDOMAIN")" \
    "$(fqdn "$QBITTORRENT_SUBDOMAIN")" \
    "$(fqdn "$NEXTCLOUD_SUBDOMAIN")" \
    "$(fqdn "$JELLYFIN_SUBDOMAIN")" \
    "$(fqdn "$PLEX_SUBDOMAIN")"
}

ensure_pi_lan_ip() {
  local detected_ip

  if [[ -n "$PI_LAN_IP" ]]; then
    return 0
  fi

  detected_ip="$(detect_lan_ip)"
  if [[ -z "$detected_ip" ]]; then
    echo "Unable to detect PI_LAN_IP; set PI_LAN_IP in .env" >&2
    return 1
  fi

  PI_LAN_IP="$detected_ip"
}