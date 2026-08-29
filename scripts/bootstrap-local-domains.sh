#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/domain.sh
source "$SCRIPT_DIR/lib/domain.sh"

generate_caddyfile() {
  local caddyfile="$ROOT_DIR/config/caddy/Caddyfile"

  mkdir -p "$(dirname "$caddyfile")"

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

http://*.$LOCAL_DOMAIN {
	respond "Unknown local service: {host}" 404
}
EOF
}

generate_coredns_hosts() {
  local coredns_hosts="$ROOT_DIR/config/coredns/hosts"

  mkdir -p "$(dirname "$coredns_hosts")"
  printf '%s ' "$PI_LAN_IP" > "$coredns_hosts"
  local_hostnames | paste -sd ' ' - >> "$coredns_hosts"
  printf '\n' >> "$coredns_hosts"
}

generate_avahi_hosts() {
  local avahi_hosts="$ROOT_DIR/config/avahi/hosts"

  mkdir -p "$(dirname "$avahi_hosts")"
  {
    echo "# BEGIN general-services local hosts"
    printf '%s ' "$PI_LAN_IP"
    local_hostnames | paste -sd ' ' -
    echo "# END general-services local hosts"
  } > "$avahi_hosts"
}

merge_managed_block() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import os
import re
import sys

target, source, begin_marker, end_marker = sys.argv[1:5]

with open(source, "r", encoding="utf-8") as file:
    block = file.read().rstrip() + "\n"

if os.path.exists(target):
    with open(target, "r", encoding="utf-8") as file:
        content = file.read()
else:
    content = ""

pattern = re.compile(
    rf"^\s*{re.escape(begin_marker)}\n.*?^\s*{re.escape(end_marker)}\n?",
    re.MULTILINE | re.DOTALL,
)
content = pattern.sub("", content).rstrip()
if content:
    content += "\n\n"
content += block

with open(target, "w", encoding="utf-8") as file:
    file.write(content)
PY
}

install_avahi_hosts() {
  local generated_hosts="$ROOT_DIR/config/avahi/hosts"
  local target_hosts="/etc/avahi/hosts"
  local begin_marker="# BEGIN general-services local hosts"
  local end_marker="# END general-services local hosts"

  if ! command -v avahi-daemon >/dev/null 2>&1; then
    echo "Avahi is not installed; generated $generated_hosts for manual mDNS alias setup" >&2
    return 0
  fi

  if [[ -w "$target_hosts" ]]; then
    merge_managed_block "$target_hosts" "$generated_hosts" "$begin_marker" "$end_marker"
    systemctl restart avahi-daemon 2>/dev/null || true
    echo "Updated Avahi mDNS aliases in $target_hosts"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo python3 - "$target_hosts" "$generated_hosts" "$begin_marker" "$end_marker" <<'PY'
import os
import re
import sys

target, source, begin_marker, end_marker = sys.argv[1:5]

with open(source, "r", encoding="utf-8") as file:
    block = file.read().rstrip() + "\n"

if os.path.exists(target):
    with open(target, "r", encoding="utf-8") as file:
        content = file.read()
else:
    content = ""

pattern = re.compile(
    rf"^\s*{re.escape(begin_marker)}\n.*?^\s*{re.escape(end_marker)}\n?",
    re.MULTILINE | re.DOTALL,
)
content = pattern.sub("", content).rstrip()
if content:
    content += "\n\n"
content += block

with open(target, "w", encoding="utf-8") as file:
    file.write(content)
PY
    sudo systemctl restart avahi-daemon 2>/dev/null || true
    echo "Updated Avahi mDNS aliases in $target_hosts"
    return 0
  fi

  echo "Generated $generated_hosts. Run this script with sudo or copy that managed block into $target_hosts to advertise mDNS aliases." >&2
}

generate_windows_hosts_script() {
  local script_path="$ROOT_DIR/generated/install-local-hosts-windows.ps1"
  local hostnames_file

  hostnames_file="$(mktemp)"
  local_hostnames > "$hostnames_file"

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
  generate_coredns_hosts
  generate_avahi_hosts
  generate_windows_hosts_script
  install_avahi_hosts

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