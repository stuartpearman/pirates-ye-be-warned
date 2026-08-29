#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--all|--auth-only|--domains-only]

Options:
  --all           Run local-domain setup and service auth setup. Default.
  --auth-only     Run only service auth/setup modules.
  --domains-only  Run only local-domain, Caddy, mDNS, and client script setup.
  -h, --help      Show this help.
EOF
}

run_domains=true
run_auth=true

while (($#)); do
  case "$1" in
    --all)
      run_domains=true
      run_auth=true
      ;;
    --auth-only)
      run_domains=false
      run_auth=true
      ;;
    --domains-only)
      run_domains=true
      run_auth=false
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

if [[ "$run_domains" == true ]]; then
  "$SCRIPT_DIR/bootstrap-local-domains.sh"
fi

if [[ "$run_auth" == true ]]; then
  "$SCRIPT_DIR/bootstrap-qbittorrent.sh"
  "$SCRIPT_DIR/bootstrap-arr.sh"
  "$SCRIPT_DIR/bootstrap-jellyfin.sh"
  "$SCRIPT_DIR/bootstrap-nextcloud.sh"
fi

echo "Bootstrap complete"