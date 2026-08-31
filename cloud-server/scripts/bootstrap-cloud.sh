#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

usage() {
  cat <<'EOF'
Usage: cloud-server/scripts/bootstrap-cloud.sh [--check]

Options:
  --check   Generate config and validate compose without starting services.
  -h, --help
            Show this help.
EOF
}

check_only=false
while (($#)); do
  case "$1" in
    --check)
      check_only=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy cloud-server/.env.example to cloud-server/.env and edit it first." >&2
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" == *=* ]] || continue

  key="${line%%=*}"
  value="${line#*=}"
  key="${key#${key%%[![:space:]]*}}"
  key="${key%${key##*[![:space:]]}}"

  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  export "$key=$value"
done < "$ENV_FILE"

PUBLIC_DOMAIN="${PUBLIC_DOMAIN:?set PUBLIC_DOMAIN in cloud-server/.env}"
VPS_PUBLIC_IP="${VPS_PUBLIC_IP:-203.0.113.10}"
ACME_EMAIL="${ACME_EMAIL:?set ACME_EMAIL in cloud-server/.env}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:?set FRP_AUTH_TOKEN in cloud-server/.env}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_HTTP_VHOST_PORT="${FRP_HTTP_VHOST_PORT:-8080}"
PLEX_SUBDOMAIN="${PLEX_SUBDOMAIN:-plex}"
PLEX_DIRECT_REMOTE_PORT="${PLEX_DIRECT_REMOTE_PORT:-32400}"
NEXTCLOUD_SUBDOMAIN="${NEXTCLOUD_SUBDOMAIN:-nextcloud}"
JELLYFIN_SUBDOMAIN="${JELLYFIN_SUBDOMAIN:-jelly}"

if [[ "$FRP_AUTH_TOKEN" == "replace-with-a-long-random-token" ]]; then
  echo "Replace FRP_AUTH_TOKEN in cloud-server/.env before starting the cloud stack." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/generated/caddy" "$ROOT_DIR/generated/frp" "$ROOT_DIR/data/caddy/data" "$ROOT_DIR/data/caddy/config"

cat > "$ROOT_DIR/generated/frp/frps.toml" <<EOF
bindPort = $FRP_BIND_PORT
vhostHTTPPort = $FRP_HTTP_VHOST_PORT

auth.method = "token"
auth.token = "$FRP_AUTH_TOKEN"

transport.tls.force = true
EOF

cat > "$ROOT_DIR/generated/caddy/Caddyfile" <<EOF
{
	email $ACME_EMAIL
}

$(printf '%s.%s' "$PLEX_SUBDOMAIN" "$PUBLIC_DOMAIN") {
	reverse_proxy frps:$FRP_HTTP_VHOST_PORT
}

$(printf '%s.%s' "$NEXTCLOUD_SUBDOMAIN" "$PUBLIC_DOMAIN") {
	reverse_proxy frps:$FRP_HTTP_VHOST_PORT
}

$(printf '%s.%s' "$JELLYFIN_SUBDOMAIN" "$PUBLIC_DOMAIN") {
	reverse_proxy frps:$FRP_HTTP_VHOST_PORT
}
EOF

(cd "$ROOT_DIR" && docker compose config --quiet)

if [[ "$check_only" == true ]]; then
  echo "Cloud config generated and compose validation passed."
  exit 0
fi

(cd "$ROOT_DIR" && docker compose up -d)

cat <<EOF
Cloud tunnel server is starting.

Create DNS-only A records pointing to this VPS IP:
  $(printf '%s.%s' "$PLEX_SUBDOMAIN" "$PUBLIC_DOMAIN")       A  $VPS_PUBLIC_IP
  $(printf '%s.%s' "$NEXTCLOUD_SUBDOMAIN" "$PUBLIC_DOMAIN")  A  $VPS_PUBLIC_IP
  $(printf '%s.%s' "$JELLYFIN_SUBDOMAIN" "$PUBLIC_DOMAIN")    A  $VPS_PUBLIC_IP

Direct Plex TCP access will listen on:
  $(printf '%s.%s' "$PLEX_SUBDOMAIN" "$PUBLIC_DOMAIN"):$PLEX_DIRECT_REMOTE_PORT
  $VPS_PUBLIC_IP:$PLEX_DIRECT_REMOTE_PORT

Then configure and start the home frpc client with:
  scripts/bootstrap-cloud-client.sh
  docker compose up -d frpc
EOF