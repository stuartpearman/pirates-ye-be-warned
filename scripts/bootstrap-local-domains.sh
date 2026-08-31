#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/domain.sh
source "$SCRIPT_DIR/lib/domain.sh"

ensure_file_path() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  if [[ -d "$path" ]]; then
    rm -rf "$path"
  fi
}

generate_caddyfile() {
  local caddyfile="$ROOT_DIR/config/caddy/Caddyfile"

  ensure_file_path "$caddyfile"

  cat > "$caddyfile" <<EOF
{
	auto_https off
}

http://$(fqdn "$HOMEPAGE_SUBDOMAIN") {
	reverse_proxy homepage:3000
}

http://$(fqdn "$LIDARR_SUBDOMAIN") {
	reverse_proxy gluetun:8686
}

http://$(fqdn "$PROWLARR_SUBDOMAIN") {
	reverse_proxy gluetun:9696
}

http://$(fqdn "$QBITTORRENT_SUBDOMAIN") {
	reverse_proxy gluetun:8090
}

http://$(fqdn "$NEXTCLOUD_SUBDOMAIN") {
	reverse_proxy nextcloud:80
}

http://$(fqdn "$JELLYFIN_SUBDOMAIN") {
	reverse_proxy jellyfin:8096
}

http://$(fqdn "$PLEX_SUBDOMAIN") {
	reverse_proxy plex:32400
}

http://$LOCAL_DOMAIN {
	reverse_proxy homepage:3000
}

http://*.$LOCAL_DOMAIN {
	respond "Unknown local service: {host}" 404
}
EOF
}

generate_coredns_corefile() {
  local corefile="$ROOT_DIR/config/coredns/Corefile"

  ensure_file_path "$corefile"

  cat > "$corefile" <<'EOF'
.:53 {
	errors
	log
	hosts /etc/coredns/hosts {
		fallthrough
	}
	forward . 1.1.1.1 8.8.8.8
	cache 30
}
EOF
}

generate_coredns_hosts() {
  local coredns_hosts="$ROOT_DIR/config/coredns/hosts"

  ensure_file_path "$coredns_hosts"
  printf '%s ' "$PI_LAN_IP" > "$coredns_hosts"
  all_local_hostnames | paste -sd ' ' - >> "$coredns_hosts"
  printf '\n' >> "$coredns_hosts"
}

generate_avahi_alias_script() {
  local alias_script="$ROOT_DIR/generated/avahi/publish-mdns-aliases.sh"

  ensure_file_path "$alias_script"

  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'pids=()'
    echo 'cleanup() {'
    echo '  for pid in "${pids[@]}"; do'
    echo '    kill "$pid" 2>/dev/null || true'
    echo '  done'
    echo '}'
    echo 'trap cleanup EXIT INT TERM'
    while IFS= read -r hostname; do
      printf 'avahi-publish-address -a -R %q %q &\n' "$hostname" "$PI_LAN_IP"
      echo 'pids+=("$!")'
    done < <(mdns_hostnames)
    echo 'wait'
  } > "$alias_script"

  chmod +x "$alias_script"
}

install_avahi_alias_service() {
  local alias_script="$ROOT_DIR/generated/avahi/publish-mdns-aliases.sh"
  local service_file="$ROOT_DIR/generated/avahi/general-services-mdns-aliases.service"
  local target_service="/etc/systemd/system/general-services-mdns-aliases.service"

  if ! command -v avahi-daemon >/dev/null 2>&1; then
    echo "Avahi is not installed; generated $alias_script for manual mDNS alias publishing" >&2
    return 0
  fi

  ensure_file_path "$service_file"

  cat > "$service_file" <<EOF
[Unit]
Description=Publish general-services mDNS aliases
After=network-online.target avahi-daemon.service
Wants=network-online.target
Requires=avahi-daemon.service

[Service]
Type=simple
ExecStart=$alias_script
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo cp "$service_file" "$target_service"
    sudo systemctl daemon-reload
    sudo systemctl enable --now general-services-mdns-aliases.service >/dev/null
    sudo systemctl restart general-services-mdns-aliases.service
    echo "Installed Avahi mDNS alias publisher service: general-services-mdns-aliases.service"
    return 0
  fi

  echo "Generated $service_file and $alias_script. Run with sudo to install the mDNS alias service." >&2
}

generate_windows_hosts_script() {
  local script_path="$ROOT_DIR/generated/install-local-hosts-windows.ps1"
  local hostnames_file

  ensure_file_path "$script_path"
  hostnames_file="$(mktemp)"
  all_local_hostnames > "$hostnames_file"

  python3 - "$script_path" "$hostnames_file" "$PI_LAN_IP" "$LOCAL_DOMAIN" "$(fqdn "$HOMEPAGE_SUBDOMAIN")" <<'PY'
import sys

script_path, hostnames_path, pi_ip, local_domain, homepage_host = sys.argv[1:6]

with open(hostnames_path, "r", encoding="utf-8") as file:
    hostnames = [line.strip() for line in file if line.strip()]

host_array = ",\n".join(f'    "{hostname}"' for hostname in hostnames)
content = fr'''param(
    [string]$PiIp = "{pi_ip}"
)

$ErrorActionPreference = "Stop"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {{
    throw "Run this script from an elevated PowerShell session."
}}

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$begin = "# BEGIN general-services local hosts"
$end = "# END general-services local hosts"
$hostNames = @(
{host_array}
)

$entries = @($begin)
foreach ($hostName in $hostNames) {{
    $entries += "$PiIp`t$hostName"
}}
$entries += $end
$block = ($entries -join [Environment]::NewLine) + [Environment]::NewLine

$content = ""
if (Test-Path $hostsPath) {{
    $content = Get-Content -Raw -Path $hostsPath
}}

$pattern = "(?ms)^\s*" + [regex]::Escape($begin) + "\r?\n.*?^\s*" + [regex]::Escape($end) + "\r?\n?"
$content = [regex]::Replace($content, $pattern, "").TrimEnd()
if ($content.Length -gt 0) {{
    $content += [Environment]::NewLine + [Environment]::NewLine
}}
$content += $block

Set-Content -Path $hostsPath -Value $content -Encoding ASCII
ipconfig /flushdns | Out-Null

Write-Host "Configured local hosts for {local_domain} -> $PiIp"
Write-Host "Open http://{homepage_host} or any configured service hostname."
'''

with open(script_path, "w", encoding="utf-8", newline="\r\n") as file:
    file.write(content)
PY

  rm -f "$hostnames_file"
}

configure_local_domains() {
  require_command docker
  require_command python3
  ensure_pi_lan_ip

  generate_caddyfile
  generate_coredns_corefile
  generate_coredns_hosts
  generate_avahi_alias_script
  generate_windows_hosts_script
  install_avahi_alias_service

  compose up -d caddy localdns >/dev/null
  compose restart caddy localdns >/dev/null

  echo "Configured local domains for $LOCAL_DOMAIN at $PI_LAN_IP"
}

main() {
  load_env
  init_common_env
  init_domain_env
  configure_local_domains
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi