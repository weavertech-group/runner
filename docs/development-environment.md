# Runner development environment

Every runner session installs the Ubuntu 24.04 development environment and the
current Codex and Claude Code CLIs. The setup is intentionally happy-path: tool
commands write their normal output to the Actions log and stop the job when they
fail.

Pinned base-tool versions live in `scripts/development-versions.env`. The shared
installer remains a script because both the private-session and cache-prewarm
workflows use the same multi-tool setup. It installs system packages, uv, mise,
Python, Go, Rust, Terraform, OpenTofu, Playwright, migrate, and Kubernetes
plugins. It also installs `runner-bootstrap` for an operator to prepare a cloned
target repository on demand.

The workflows restore and save the development-tool cache using the version-file
hash. Dispatch **Prepare Development Cache** to prewarm it after a version
change.

The runner does not install project dependencies automatically. After connecting
over SSH, run:

```bash
cd /path/to/repository
runner-bootstrap
```

For local validation:

```bash
bash tests/happy-path-workflow.test.sh
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
```
