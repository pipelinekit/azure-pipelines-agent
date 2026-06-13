# Azure Pipelines Agent — Docker & Linux Installer

Run the [Azure Pipelines self-hosted agent](https://github.com/microsoft/azure-pipelines-agent)
anywhere — as a container or as a native Linux service. This repository provides a
production-ready **Dockerfile**, a **native `install.sh`** that registers a systemd
service, and **GitHub Actions** workflows that build and publish multi-arch images
to the GitHub Container Registry (GHCR).

[![CI](https://github.com/pipelinekit/azure-pipelines-agent/actions/workflows/ci.yml/badge.svg)](https://github.com/pipelinekit/azure-pipelines-agent/actions/workflows/ci.yml)
[![Build and Publish](https://github.com/pipelinekit/azure-pipelines-agent/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/pipelinekit/azure-pipelines-agent/actions/workflows/docker-publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

- 🐳 **Multi-arch Docker image** (`linux/amd64`, `linux/arm64`)
- ♻️ **Self-cleaning** — the agent unregisters itself from the pool on container stop
- 🐧 **Native installer** — `install.sh` sets up a systemd service in one command
- 🔁 **Auto-updating** — weekly scheduled rebuilds pick up new agent & base-image patches
- 🔐 **Supply-chain hardened** — SBOM, build provenance, and signed attestations
- ✅ **CI** — ShellCheck, hadolint, and a build smoke test on every PR

---

## Quick start

### Prerequisites

1. An Azure DevOps organization, e.g. `https://dev.azure.com/your-org`.
2. An agent **pool** (create one under *Organization settings → Agent pools*).
3. A **Personal Access Token (PAT)** with the **Agent Pools (Read & manage)** scope.

### Option A — Docker (single agent)

```bash
docker run -d --restart unless-stopped \
  -e AZP_URL="https://dev.azure.com/your-org" \
  -e AZP_TOKEN="<your-pat>" \
  -e AZP_POOL="Default" \
  --name azp-agent \
  ghcr.io/pipelinekit/azure-pipelines-agent:latest
```

### Option B — Docker Compose (one or many agents)

```bash
cp .env.example .env       # then edit .env with your values
docker compose up -d
docker compose up -d --scale agent=3   # run 3 agents
```

### Option C — Native Linux install (systemd)

**One-line install with `curl`** (no clone needed):

```bash
curl -fsSL https://raw.githubusercontent.com/pipelinekit/azure-pipelines-agent/main/install.sh \
  | sudo sh -s -- \
      --url   https://dev.azure.com/your-org \
      --token <your-pat> \
      --pool  Default
```

> The scripts are POSIX `sh` (no bash required). Piping to `sudo sh` runs a
> remote script as root — inspect it first if you prefer:
> `curl -fsSL .../install.sh | less`, or clone and run it manually below.

**Or from a clone:**

```bash
git clone https://github.com/pipelinekit/azure-pipelines-agent.git
cd azure-pipelines-agent
sudo ./install.sh \
  --url   https://dev.azure.com/your-org \
  --token <your-pat> \
  --pool  Default
```

Manage it afterwards from the install dir (`/opt/azp-agent` by default):

```bash
cd /opt/azp-agent
sudo ./svc.sh status
sudo ./svc.sh stop
sudo ./svc.sh start
```

Uninstall (also unregisters the agent from the pool):

```bash
curl -fsSL https://raw.githubusercontent.com/pipelinekit/azure-pipelines-agent/main/uninstall.sh \
  | sudo sh -s -- --token <your-pat>
```

---

## Configuration

All entrypoint behavior is driven by environment variables.

| Variable         | Required | Default            | Description                                        |
| ---------------- | :------: | ------------------ | -------------------------------------------------- |
| `AZP_URL`        |    ✅    | —                  | Azure DevOps organization URL                      |
| `AZP_TOKEN`      |    ✅    | —                  | PAT with *Agent Pools (Read & manage)*             |
| `AZP_TOKEN_FILE` |          | —                  | Path to a file containing the PAT (Docker secrets) |
| `AZP_POOL`       |          | `Default`          | Agent pool name                                    |
| `AZP_AGENT_NAME` |          | container hostname | Agent display name                                 |
| `AZP_WORK`       |          | `_work`            | Work directory                                     |

> **Tip:** prefer `AZP_TOKEN_FILE` with [Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
> over passing the PAT inline, so the token never appears in `docker inspect`.

### `install.sh` flags

```text
--url <url>          Azure DevOps organization URL          (required)
--token <pat>        Personal Access Token                  (required)
--pool <name>        Agent pool name                        (default: Default)
--name <name>        Agent name                             (default: hostname)
--work <dir>         Work directory                         (default: _work)
--version <ver>      Agent version to install               (default: latest)
--install-dir <dir>  Install location                       (default: /opt/azp-agent)
--user <user>        Service account                        (default: azp-agent)
--no-deps            Skip installdependencies.sh
```

---

## Building locally

```bash
# Pinned default agent version (reproducible)
docker build -t azp-agent:local .

# Pin a specific agent version
docker build --build-arg AZP_AGENT_VERSION=4.274.1 -t azp-agent:local .

# Resolve the newest release at build time
docker build --build-arg AZP_AGENT_VERSION=latest -t azp-agent:local .
```

---

## Publishing (GitHub Actions)

`.github/workflows/docker-publish.yml` builds and pushes multi-arch images to
`ghcr.io/pipelinekit/azure-pipelines-agent` on:

- pushes to `main` → `latest` + `main` + short-SHA tags
- semver tags `vX.Y.Z` → `X.Y.Z`, `X.Y`, `X` tags
- a **weekly schedule** → fresh agent + base-image patches
- manual `workflow_dispatch` (optionally pin an agent version)

No extra secrets are required — it authenticates with the built-in
`GITHUB_TOKEN`. To consume the published image, make the GHCR package public, or
authenticate with a token that has `read:packages`.

---

## Docker-in-Docker (building images inside pipelines)

If your pipelines build container images, mount the host Docker socket:

```bash
docker run -d --restart unless-stopped \
  -e AZP_URL="https://dev.azure.com/your-org" \
  -e AZP_TOKEN="<your-pat>" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/pipelinekit/azure-pipelines-agent:latest
```

> Mounting the Docker socket grants the container root-equivalent access to the
> host. Only do this on trusted infrastructure.

---

## How it works

- **`Dockerfile`** — Ubuntu base, installs runtime deps, downloads the agent
  tarball (version pinned via `AZP_AGENT_VERSION` or resolved to the latest
  GitHub release), runs as an unprivileged `agent` user.
- **`start.sh`** — configures the agent unattended, runs it in the foreground,
  and traps `SIGINT`/`SIGTERM` to **unregister** the agent from the pool on stop.
- **`install.sh` / `uninstall.sh`** — native install path using the agent's own
  `svc.sh` to manage a systemd unit.

---

## Troubleshooting

| Symptom                          | Likely cause / fix                                                        |
| -------------------------------- | ------------------------------------------------------------------------- |
| `missing AZP_URL` / `AZP_TOKEN`  | Set the required environment variables.                                   |
| `TF400813: ... not authorized`   | PAT is invalid/expired or missing *Agent Pools (Read & manage)*.          |
| Agent stuck "offline" after stop | Pass `--token` to `uninstall.sh`, or remove it manually from the pool UI. |
| `403` while downloading agent    | The agent version doesn't exist for that architecture; check `--version`. |

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and our
[Code of Conduct](CODE_OF_CONDUCT.md) before opening a PR.

## Security

Found a vulnerability? Please follow our [Security Policy](SECURITY.md) — do not
open a public issue for security reports.

## License

[MIT](LICENSE). This project packages the Azure Pipelines Agent, which is
distributed by Microsoft under the MIT License. The agent binary is downloaded
at build/run time and is **not** redistributed here. This repository is **not**
affiliated with or endorsed by Microsoft.
