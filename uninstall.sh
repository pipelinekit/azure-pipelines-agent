#!/bin/sh
set -eu

# ===========================================================================
# Azure Pipelines Agent — native Linux uninstaller
#
# Stops the systemd service, unregisters the agent from Azure DevOps, and
# removes the installation directory.
#
# Usage:
#   sudo ./uninstall.sh --install-dir /opt/azp-agent --token <PAT>
# ===========================================================================

INSTALL_DIR="/opt/azp-agent"
AZP_TOKEN=""
RUN_USER="azp-agent"
REMOVE_USER="false"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Azure Pipelines Agent — uninstaller

Usage:
  sudo ./uninstall.sh [options]

Options:
  --install-dir <dir>  Install location          (default: /opt/azp-agent)
  --token <pat>        PAT used to unregister the agent (recommended)
  --user <user>        Service account            (default: azp-agent)
  --remove-user        Also delete the service user account
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --token)       AZP_TOKEN="$2"; shift 2 ;;
        --user)        RUN_USER="$2"; shift 2 ;;
        --remove-user) REMOVE_USER="true"; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "this script must be run as root (use sudo)"
[ -d "$INSTALL_DIR" ] || die "install directory not found: $INSTALL_DIR"

log "Stopping and uninstalling service..."
(cd "$INSTALL_DIR" && ./svc.sh stop) || warn "could not stop service"
(cd "$INSTALL_DIR" && ./svc.sh uninstall) || warn "could not uninstall service"

if [ -n "$AZP_TOKEN" ] && [ -f "${INSTALL_DIR}/config.sh" ]; then
    log "Unregistering agent from Azure DevOps..."
    sudo -u "$RUN_USER" -- sh -c "cd '$INSTALL_DIR' && ./config.sh remove \
        --unattended --auth PAT --token '$AZP_TOKEN'" \
        || warn "could not unregister agent (remove it manually from the pool)"
else
    warn "no --token provided; remove the agent manually from the Azure DevOps pool"
fi

log "Removing ${INSTALL_DIR}"
rm -rf "$INSTALL_DIR"

if [ "$REMOVE_USER" = "true" ] && id "$RUN_USER" >/dev/null 2>&1; then
    log "Removing service user ${RUN_USER}"
    userdel -r "$RUN_USER" 2>/dev/null || warn "could not fully remove user ${RUN_USER}"
fi

log "Uninstall complete."
