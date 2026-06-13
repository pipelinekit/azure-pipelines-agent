# Security Policy

## Reporting a vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, use **[GitHub Security Advisories](../../security/advisories/new)**
(*Security → Advisories → Report a vulnerability*). This keeps the report
private until a fix is available.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (proof of concept if possible)
- Affected version(s) / image tags
- Any suggested mitigation

You can expect an initial acknowledgement within **5 business days**. We will
keep you informed of progress toward a fix and coordinate disclosure timing
with you.

## Scope

This repository packages and runs the upstream
[Azure Pipelines Agent](https://github.com/microsoft/azure-pipelines-agent).
Vulnerabilities in the **agent itself** should be reported to Microsoft. Issues
in **this project's** Dockerfile, scripts, or workflows are in scope here.

## Hardening notes for operators

- Store the PAT as a secret. Prefer `AZP_TOKEN_FILE` (Docker secrets) over
  passing `AZP_TOKEN` inline so it doesn't appear in `docker inspect`.
- Use a PAT with the **least** required scope (*Agent Pools: Read & manage*) and
  the shortest practical expiry; rotate regularly.
- The container runs as a non-root `agent` user by default. Avoid
  `AGENT_ALLOW_RUNASROOT=true` unless you understand the implications.
- Mounting `/var/run/docker.sock` grants host-root-equivalent access. Only do so
  on trusted, isolated infrastructure.
- Published images include an SBOM and signed build provenance — verify them
  with `cosign`/`gh attestation verify` before deploying to sensitive
  environments.
