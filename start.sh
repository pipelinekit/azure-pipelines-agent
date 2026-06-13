#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# Entrypoint for the Azure Pipelines containerized agent.
#
# Required environment variables:
#   AZP_URL    - Azure DevOps organization URL (https://dev.azure.com/your-org)
#   AZP_TOKEN  - Personal Access Token with "Agent Pools (read, manage)" scope
#
# Optional:
#   AZP_POOL        - Agent pool name (default: "Default")
#   AZP_AGENT_NAME  - Agent name (default: container hostname)
#   AZP_WORK        - Work directory (default: "_work")
# ---------------------------------------------------------------------------

if [ -z "${AZP_URL:-}" ]; then
    echo 1>&2 "error: missing AZP_URL environment variable"
    exit 1
fi

if [ -z "${AZP_TOKEN:-}" ]; then
    if [ -n "${AZP_TOKEN_FILE:-}" ] && [ -f "${AZP_TOKEN_FILE}" ]; then
        AZP_TOKEN="$(cat "${AZP_TOKEN_FILE}")"
    else
        echo 1>&2 "error: missing AZP_TOKEN environment variable (or AZP_TOKEN_FILE)"
        exit 1
    fi
fi

export AGENT_ALLOW_RUNASROOT="${AGENT_ALLOW_RUNASROOT:-false}"
AZP_POOL="${AZP_POOL:-Default}"
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)}"
AZP_WORK="${AZP_WORK:-_work}"

cleanup() {
    trap "" EXIT

    if [ -e ./config.sh ]; then
        echo "Removing agent from the pool..."
        # Retry removal a few times in case of transient failures.
        for _ in 1 2 3; do
            if ./config.sh remove --unattended --auth "PAT" --token "${AZP_TOKEN}"; then
                break
            fi
            echo "Retrying agent removal in 5 seconds..."
            sleep 5
        done
    fi
}

print_header() {
    printf '\n\033[1;36m%s\033[0m\n\n' "$1"
}

# Let the agent know we will manage its lifecycle.
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "1. Configuring Azure Pipelines agent..."

./config.sh \
    --unattended \
    --agent "${AZP_AGENT_NAME}" \
    --url "${AZP_URL}" \
    --auth "PAT" \
    --token "${AZP_TOKEN}" \
    --pool "${AZP_POOL}" \
    --work "${AZP_WORK}" \
    --replace \
    --acceptTeeEula

print_header "2. Running Azure Pipelines agent..."

# Unregister the agent on container stop (SIGINT / SIGTERM).
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# Run the agent in the foreground; `&` + `wait` lets traps fire immediately.
./run.sh "$@" &
wait $!
