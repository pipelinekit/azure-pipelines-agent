# Contributing

Thanks for taking the time to contribute! This document explains how to propose
changes to this project.

## Ways to contribute

- 🐛 Report bugs via [issues](../../issues)
- 💡 Suggest features or improvements
- 📖 Improve the documentation
- 🔧 Submit pull requests

## Development setup

You only need Docker (with Buildx) and a POSIX shell.

```bash
# Build the image
docker build -t azp-agent:dev .

# Lint shell scripts
shellcheck start.sh install.sh uninstall.sh

# Lint the Dockerfile
docker run --rm -i hadolint/hadolint < Dockerfile
```

CI runs the same checks (ShellCheck, hadolint, and a build smoke test) on every
pull request, so please run them locally first.

## Pull request process

1. Fork the repository and create a branch from `main`
   (e.g. `feat/arm-support`, `fix/cleanup-trap`).
2. Make your change. Keep it focused — one logical change per PR.
3. Ensure ShellCheck and hadolint pass and the image builds.
4. Update `README.md` / docs if behavior or options changed.
5. Use clear, [Conventional Commits](https://www.conventionalcommits.org/)-style
   messages where practical (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).
6. Open the PR and fill in the template. Link any related issues.

## Coding style

- **Shell:** `bash`, `set -euo pipefail`, quote your variables, prefer `printf`
  over `echo` for messages, keep functions small.
- **Dockerfile:** minimize layers, clean up apt caches, pin where it makes sense.
- Match the style of the surrounding code.

## Reporting security issues

Please **do not** open public issues for security vulnerabilities. See
[SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
