# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Azure Pipelines self-hosted agent
# Builds a container image that downloads and runs the Azure Pipelines agent
# from https://github.com/microsoft/azure-pipelines-agent
# ---------------------------------------------------------------------------
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

# Pinned agent version (reproducible builds). Override at build time:
#   docker build --build-arg AZP_AGENT_VERSION=4.274.1 .
# Set to "latest" to resolve the newest release from the GitHub API instead.
ARG AZP_AGENT_VERSION=4.274.1
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive
ENV AGENT_ALLOW_RUNASROOT="false"

# Fail pipelines on the first non-zero command (hadolint DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base dependencies required by the agent and most pipeline tasks.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        unzip \
        tar \
        gzip \
        libicu70 \
        libkrb5-3 \
        zlib1g \
        liblttng-ust1 \
        libssl3 \
        lsb-release \
        sudo \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create an unprivileged user to run the agent.
RUN useradd -m -s /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

WORKDIR /azp

# Download and extract the agent.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) AZP_ARCH="x64" ;; \
        arm64) AZP_ARCH="arm64" ;; \
        arm)   AZP_ARCH="arm" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ -z "${AZP_AGENT_VERSION}" ] || [ "${AZP_AGENT_VERSION}" = "latest" ]; then \
        AZP_AGENT_VERSION="$(curl -fsSL https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name' | sed 's/^v//')"; \
    fi; \
    if [ -z "${AZP_AGENT_VERSION}" ] || [ "${AZP_AGENT_VERSION}" = "null" ]; then \
        echo "Could not determine agent version" >&2; exit 1; \
    fi; \
    echo "Installing agent version ${AZP_AGENT_VERSION} (${AZP_ARCH})"; \
    AZP_PACKAGE="vsts-agent-linux-${AZP_ARCH}-${AZP_AGENT_VERSION}.tar.gz"; \
    curl -fsSL --retry 5 --retry-delay 5 -o /tmp/agent.tar.gz \
        "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/${AZP_PACKAGE}"; \
    tar -xzf /tmp/agent.tar.gz -C /azp; \
    rm -f /tmp/agent.tar.gz; \
    chown -R agent:agent /azp

# Install agent-level external dependencies (kerberos, openssl, etc.).
RUN ./bin/installdependencies.sh || true

COPY --chown=agent:agent start.sh /azp/start.sh
RUN chmod +x /azp/start.sh

USER agent

ENTRYPOINT ["/azp/start.sh"]
