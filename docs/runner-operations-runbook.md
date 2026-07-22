# Private runner operations

## Start a session

Dispatch **Private T3 Session** and choose the protected GitHub Environment
holding the target-repository secrets. Set `enable_ssh=true` for private shell
access. Set `non_durable=true` only when the workflow should finish after it
has started and reported T3 rather than remain available.

## Connect

With the default Tailscale SSH mode:

```bash
tailscale ssh runner@gha-<run-id>-<run-attempt>
```

Read the private connection data after connecting:

```bash
cat ~/private-runner-session/t3code/connection.txt
```

The file is mode `0600`. Do not copy its pairing URL to Actions output,
artifacts, or an untrusted chat.

## Failure behavior

This repository follows the happy path. Native commands keep their normal
output and exit status; the workflow has no custom retry, timeout, fallback, or
diagnostic-artifact layer.

## Local checks

```bash
bash tests/workflow-security.test.sh
python3 tests/report_lark_test.py
shellcheck --severity=bash tests/*.sh
actionlint
```
