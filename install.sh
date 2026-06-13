#!/usr/bin/env bash
set -euo pipefail

# ===========================================================================
# Azure Pipelines Agent — native Linux installer
#
# Installs the Azure Pipelines self-hosted agent
# (https://github.com/microsoft/azure-pipelines-agent) directly on a Linux
# host and registers it as a systemd service.
#
# Usage:
#   sudo ./install.sh --url https://dev.azure.com/org --token <PAT> [options]
#
# Run with --help for the full option list.
# ===========================================================================

# ----------------------------- defaults ------------------------------------
AZP_URL=""
AZP_TOKEN=""
AZP_POOL="Default"
AZP_AGENT_NAME="$(hostname)"
AZP_WORK="_work"
AZP_AGENT_VERSION=""
INSTALL_DIR="/opt/azp-agent"
RUN_USER="azp-agent"
INSTALL_DEPS="true"

GITHUB_API="https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest"

# ----------------------------- helpers -------------------------------------
log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Azure Pipelines Agent — native Linux installer

Usage:
  sudo ./install.sh --url <ORG_URL> --token <PAT> [options]

Required:
  --url <url>          Azure DevOps organization URL
                       (e.g. https://dev.azure.com/your-org)
  --token <pat>        Personal Access Token (Agent Pools: read & manage)

Options:
  --pool <name>        Agent pool name              (default: Default)
  --name <name>        Agent name                   (default: hostname)
  --work <dir>         Work directory               (default: _work)
  --version <ver>      Agent version to install     (default: latest release)
  --install-dir <dir>  Install location             (default: /opt/azp-agent)
  --user <user>        Service account to run as    (default: azp-agent)
  --no-deps            Skip installdependencies.sh
  -h, --help           Show this help

Environment variables (AZP_URL, AZP_TOKEN, ...) are honored as fallbacks.
EOF
}

# ----------------------------- arg parsing ---------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --url)         AZP_URL="$2"; shift 2 ;;
        --token)       AZP_TOKEN="$2"; shift 2 ;;
        --pool)        AZP_POOL="$2"; shift 2 ;;
        --name)        AZP_AGENT_NAME="$2"; shift 2 ;;
        --work)        AZP_WORK="$2"; shift 2 ;;
        --version)     AZP_AGENT_VERSION="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --user)        RUN_USER="$2"; shift 2 ;;
        --no-deps)     INSTALL_DEPS="false"; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

# Fall back to environment variables.
AZP_URL="${AZP_URL:-${AZP_URL_ENV:-}}"
AZP_TOKEN="${AZP_TOKEN:-${AZP_TOKEN_ENV:-}}"

# ----------------------------- validation ----------------------------------
[ "$(id -u)" -eq 0 ] || die "this script must be run as root (use sudo)"
[ -n "$AZP_URL" ]   || die "missing --url (or AZP_URL)"
[ -n "$AZP_TOKEN" ] || die "missing --token (or AZP_TOKEN)"

command -v curl >/dev/null 2>&1 || die "curl is required but not installed"
command -v tar  >/dev/null 2>&1 || die "tar is required but not installed"

# ----------------------------- architecture --------------------------------
case "$(uname -m)" in
    x86_64|amd64) AZP_ARCH="x64" ;;
    aarch64|arm64) AZP_ARCH="arm64" ;;
    armv7l|armhf) AZP_ARCH="arm" ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

# ----------------------------- resolve version -----------------------------
if [ -z "$AZP_AGENT_VERSION" ]; then
    log "Resolving latest agent version from GitHub..."
    if command -v jq >/dev/null 2>&1; then
        AZP_AGENT_VERSION="$(curl -fsSL "$GITHUB_API" | jq -r '.tag_name' | sed 's/^v//')"
    else
        AZP_AGENT_VERSION="$(curl -fsSL "$GITHUB_API" \
            | grep -m1 '"tag_name"' \
            | sed -E 's/.*"v?([^"]+)".*/\1/')"
    fi
    [ -n "$AZP_AGENT_VERSION" ] || die "could not resolve latest agent version"
fi
log "Agent version: ${AZP_AGENT_VERSION} (${AZP_ARCH})"

# ----------------------------- service user --------------------------------
if ! id "$RUN_USER" >/dev/null 2>&1; then
    log "Creating service user: ${RUN_USER}"
    useradd --system --create-home --shell /bin/bash "$RUN_USER"
fi

# ----------------------------- download ------------------------------------
log "Installing into ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

PACKAGE="vsts-agent-linux-${AZP_ARCH}-${AZP_AGENT_VERSION}.tar.gz"
TMP_TARBALL="$(mktemp)"
trap 'rm -f "$TMP_TARBALL"' EXIT

log "Downloading ${PACKAGE}"
curl -fsSL -o "$TMP_TARBALL" \
    "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/${PACKAGE}" \
    || curl -fsSL -o "$TMP_TARBALL" \
    "https://vstsagentpackage.azureedge.net/agent/${AZP_AGENT_VERSION}/${PACKAGE}" \
    || die "failed to download agent package"

tar -xzf "$TMP_TARBALL" -C "$INSTALL_DIR"
chown -R "$RUN_USER:$RUN_USER" "$INSTALL_DIR"

# ----------------------------- dependencies --------------------------------
if [ "$INSTALL_DEPS" = "true" ] && [ -f "${INSTALL_DIR}/bin/installdependencies.sh" ]; then
    log "Installing agent dependencies..."
    (cd "$INSTALL_DIR" && ./bin/installdependencies.sh) || warn "installdependencies.sh reported errors"
fi

# ----------------------------- configure -----------------------------------
log "Configuring agent '${AZP_AGENT_NAME}' in pool '${AZP_POOL}'..."
sudo -u "$RUN_USER" -- bash -c "cd '$INSTALL_DIR' && ./config.sh \
    --unattended \
    --agent '$AZP_AGENT_NAME' \
    --url '$AZP_URL' \
    --auth PAT \
    --token '$AZP_TOKEN' \
    --pool '$AZP_POOL' \
    --work '$AZP_WORK' \
    --replace \
    --acceptTeeEula"

# ----------------------------- systemd service -----------------------------
log "Installing systemd service via svc.sh..."
(cd "$INSTALL_DIR" && ./svc.sh install "$RUN_USER")
(cd "$INSTALL_DIR" && ./svc.sh start)

log "Done. Service status:"
(cd "$INSTALL_DIR" && ./svc.sh status) || true

cat <<EOF

Azure Pipelines agent installed successfully.

  Pool:        ${AZP_POOL}
  Agent name:  ${AZP_AGENT_NAME}
  Install dir: ${INSTALL_DIR}
  Run user:    ${RUN_USER}

Manage the service from ${INSTALL_DIR}:
  sudo ./svc.sh status
  sudo ./svc.sh stop
  sudo ./svc.sh start

Uninstall:
  sudo ./uninstall.sh --install-dir ${INSTALL_DIR} --token <PAT>
EOF
