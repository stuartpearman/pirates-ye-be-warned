#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env file at $ENV_FILE" >&2
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

PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-example.com}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-203.0.113.10}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:?set FRP_AUTH_TOKEN in .env to match cloud-server/.env}"
PLEX_SUBDOMAIN="${PLEX_SUBDOMAIN:-plex}"
NEXTCLOUD_SUBDOMAIN="${NEXTCLOUD_SUBDOMAIN:-nextcloud}"
JELLYFIN_SUBDOMAIN="${JELLYFIN_SUBDOMAIN:-jelly}"
PLEX_DIRECT_REMOTE_PORT="${PLEX_DIRECT_REMOTE_PORT:-32400}"

mkdir -p "$ROOT_DIR/generated/frp"

cat > "$ROOT_DIR/generated/frp/frpc.toml" <<EOF
serverAddr = "$FRP_SERVER_ADDR"
serverPort = $FRP_BIND_PORT

auth.method = "token"
auth.token = "$FRP_AUTH_TOKEN"

transport.tls.enable = true

[[proxies]]
name = "plex"
type = "http"
localIP = "127.0.0.1"
localPort = 32400
customDomains = ["$PLEX_SUBDOMAIN.$PUBLIC_DOMAIN"]

[[proxies]]
name = "plex-direct"
type = "tcp"
localIP = "127.0.0.1"
localPort = 32400
remotePort = $PLEX_DIRECT_REMOTE_PORT

[[proxies]]
name = "nextcloud"
type = "http"
localIP = "127.0.0.1"
localPort = 8081
customDomains = ["$NEXTCLOUD_SUBDOMAIN.$PUBLIC_DOMAIN"]

[[proxies]]
name = "jellyfin"
type = "http"
localIP = "127.0.0.1"
localPort = 8096
customDomains = ["$JELLYFIN_SUBDOMAIN.$PUBLIC_DOMAIN"]
EOF

echo "Generated $ROOT_DIR/generated/frp/frpc.toml"
echo "Start or restart the tunnel client with: docker compose --profile cloud-client up -d frpc"