# Runner development environment

Every valid runner session prepares an Ubuntu 24.04 development environment. Installation output and version details stay in `$RUNNER_TEMP/private-runner-diagnostics`; public workflow output contains only stable status messages and error codes.

## Fast startup behavior

When private SSH is enabled, the workflow restores available caches and connects the runner to Headscale before installing the complete development environment. This makes the runner reachable while the remaining tools are being prepared.

After connecting, inspect the local setup state:

```bash
cat ~/private-runner-session/setup-status
cat ~/private-runner-session/setup-details
```

The status is one of:

- `installing`: the complete environment is still being prepared;
- `ready`: all fixed tools, Codex CLI, and Claude Code were installed and verified;
- `degraded`: one or more setup steps failed, but the SSH session remains available for manual repair.

Repository credentials are also configured before complete development setup, so an authorized operator can clone the selected repository while installation continues.

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

Codex CLI and Claude Code are deliberate exceptions. Every session installs both tools in a single npm invocation using `@openai/codex@latest` and `@anthropic-ai/claude-code@latest`.

Downloaded uv and Kubernetes plugin archives are verified against pinned SHA-256 checksums. mise is installed from a versioned immutable release, and GitHub artifact-attestation verification is explicitly enabled for tool backends that support it.

## Cross-session caches

The privileged workflow restores two best-effort GitHub Actions caches.

The fixed development cache contains:

- mise-installed Python, Go, Rust, Terraform, and OpenTofu toolchains;
- mise shims;
- Playwright Chromium;
- the compiled `migrate` binary;
- the pinned uv, uvx, and mise executables;
- downloaded kubectx, kubens, and kubectl-neat archives.

Its key contains the operating system, architecture, and the hash of `scripts/development-versions.env`. A pinned version change therefore creates a fresh cache.

The npm download cache contains `~/.npm` and Corepack's download directory. Its key contains the Node.js version and ISO week. Codex and Claude still query npm and install `latest`; the cache only reuses package downloads when possible.

On an exact fixed-cache hit, the installer skips downloading uv and mise, skips reinstalling complete mise toolchains, skips compiling `migrate`, and avoids downloading Playwright Chromium when the expected browser cache is present. Playwright system dependencies are still installed on the fresh Ubuntu VM.

Both caches are saved immediately after their corresponding installation and verification steps, before optional DevSpace startup and the long-running session. Cache restore or save failures do not prevent the runner from starting.

## Prewarm the cache

After changing pinned versions, or before the first runner session, manually dispatch **Prepare Development Cache**. The workflow does not use Headscale, repository credentials, GitHub Environments, or DevSpace. It builds and verifies the complete environment, then exits after saving the fixed and npm caches.

The first private session after a new cache key may still perform a cold installation when no prewarm run has been completed. Later sessions with the same fixed version manifest should restore the cache.

## Project dependencies

The runner does not automatically execute dependency installation from a selected target repository. Commands such as `npm install`, package lifecycle scripts, Python build hooks, and Rust build scripts execute repository-controlled code.

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

The workflow first verifies fixed development tools without requiring Codex or Claude. After the combined AI CLI installation, it verifies the complete environment and persists Node-provided command paths under `$HOME/.local/bin` for fresh SSH login shells.

For local static validation:

```bash
bash tests/workflow-security.test.sh
bash tests/development-cache.test.sh
bash tests/startup-optimization.test.sh
bash -n scripts/*.sh tests/*.sh
```
