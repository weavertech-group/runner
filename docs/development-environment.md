# Runner development environment

Every valid runner session prepares a fixed Ubuntu 24.04 development environment before private network access is enabled. Installation output and version details stay in `$RUNNER_TEMP/private-runner-diagnostics`; public workflow output contains only stable status messages and error code `E55` on failure.

## Base command-line tools

The runner installs these Ubuntu packages for interactive SSH development:

- `tmux`
- `ripgrep` (`rg`)
- `fd-find`, exposed as `fd`
- `fzf`
- `bat`, exposed as `bat`
- `tree`
- `lsof`
- `htop`
- `socat`
- `direnv`
- compiler and native-extension prerequisites

The login profile adds `$HOME/.local/bin`, mise shims, and `$HOME/go/bin` to `PATH`. Bash enables the `direnv` hook, but a repository `.envrc` still requires explicit operator approval with `direnv allow`.

## Version policy

Pinned versions are declared in `scripts/development-versions.env`. The workflow, installer, verification script, and security test must be changed together when a pinned tool is upgraded.

The pinned environment includes:

- Ubuntu 24.04 and Node.js 22.23.1
- Corepack, pnpm, and Yarn
- uv and mise
- Python, Go, and Rust
- Terraform and OpenTofu
- Playwright with Chromium
- `golang-migrate` with PostgreSQL, MySQL, and SQLite support
- Kubernetes plugins `kubectl ctx`, `kubectl ns`, and `kubectl neat`

Codex CLI and Claude Code are the deliberate exceptions. The workflow installs `@openai/codex@latest` and `@anthropic-ai/claude-code@latest` so every new session receives their current npm releases. This makes those two tools non-reproducible by design and keeps npm availability on the critical startup path.

Downloaded uv and Kubernetes plugin archives are verified against pinned SHA-256 checksums. mise is installed from a versioned immutable release, and GitHub artifact-attestation verification is explicitly enabled for tool backends that support it.

## Cross-session cache

The privileged workflow restores and saves a GitHub Actions cache for the slowest fixed development components:

- mise-installed Python, Go, Rust, Terraform, and OpenTofu toolchains;
- mise shims;
- the Playwright Chromium browser cache;
- the compiled `migrate` binary;
- the pinned uv, uvx, and mise executables.

The cache key contains the operating system, architecture, and the hash of `scripts/development-versions.env`. Changing any pinned version automatically creates a fresh cache. Prefix restore keys are deliberately not used, so a session never restores a cache built for a different version manifest.

On an exact cache hit, the installer reuses the restored toolchains and binaries. Ubuntu packages, Corepack, pnpm, Yarn, the Playwright CLI, Kubernetes plugins, Codex CLI, and Claude Code are still refreshed during every session. Playwright checks the restored browser cache and avoids downloading Chromium again when the required build is already present.

The cache is saved before the long-running `Execute` step. Restore and save steps are best effort: a cache service failure falls back to the normal installation path and does not prevent the private runner session from starting.

## Project dependencies

The runner does not automatically execute dependency installation from a selected target repository. Commands such as `npm install`, package lifecycle scripts, Python build hooks, and Rust build scripts execute repository-controlled code. Automatically running them before the operator connects would expand the trusted workflow boundary.

After cloning and reviewing the selected repository, run:

```bash
cd /path/to/repository
runner-bootstrap
```

An explicit workspace can also be supplied:

```bash
runner-bootstrap /path/to/repository
```

The helper recognizes:

- `mise.toml`, `.mise.toml`, and `.tool-versions`;
- pnpm, Yarn, and npm lockfiles;
- `uv.lock`, `pyproject.toml`, and Python requirements files;
- `go.mod`;
- `Cargo.toml` and `Cargo.lock`;
- Playwright declared as a Node.js dependency.

Lockfiles are preferred when available. The helper uses frozen or immutable installation modes where the relevant package manager supports them.

## Verification

Before network setup, `scripts/verify-development-environment.sh` checks command discovery, exact pinned versions, the embedded Go module version of `migrate`, Kubernetes plugin discovery, and the installed Playwright browser. It also persists Node-provided command paths under `$HOME/.local/bin` so they remain available in a fresh SSH login shell.

For local static validation:

```bash
bash tests/workflow-security.test.sh
bash tests/development-cache.test.sh
bash -n scripts/*.sh tests/*.sh
```

A static test cannot prove that every upstream package download succeeds. Before merging a version update, dispatch the branch workflow in a protected test Environment and confirm that the installation and verification steps complete on GitHub's Ubuntu 24.04 image.
