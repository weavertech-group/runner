# ChatGPT app acceptance memory

This document records the changing acceptance state for the ChatGPT code-task
control plane. Stable, cross-cutting facts belong in
[project memory](../project-memory.md). It is not an execution log. Secret
values, private keys, OAuth tokens, prompts, and raw API responses must not be
copied here.

Evidence below was refreshed on 2026-07-26 unless a narrower boundary is
stated.

## Current acceptance state

| Gate | State | Evidence and boundary |
| --- | --- | --- |
| Worker typecheck | **Passed** | `npm --prefix apps/chatgpt-app run typecheck` completed successfully. |
| Workflow security contract | **Passed** | `bash tests/workflow-security.test.sh` completed successfully. |
| Complete local Node test suite | **Passed** | `node --test tests/*.test.js`: 29 passed and 0 failed. |
| Installation auto-resolution behavior | **Passed in code-level test** | The production-edge test observes repository installation lookup followed by installation-token creation and workflow dispatch. Deployment configuration contains no manual installation ID. |
| GitHub App installation | **Passed** | An App JWT authenticated `GET /repos/weavertech-group/runner/installation`. The installation covers all repositories and reports `Actions`, `Contents`, and `Pull requests: write` plus `Metadata: read`. The ID and JWT were not printed or persisted. |
| Runner GitHub App credentials | **Configured, not exercised** | `RUNNER_GITHUB_APP_ID` and `RUNNER_GITHUB_APP_PRIVATE_KEY` exist as runner repository secrets. The workflow uses these names because GitHub rejects custom secret names beginning with `GITHUB_`; no workflow run has exercised the new credentials yet. |
| Codex executor credentials | **Configured, not exercised** | `CODEX_API_KEY` and `CODEX_RESPONSES_API_ENDPOINT` exist as runner repository secrets. They were uploaded from the local provider configuration through stdin without printing their values. No workflow run has exercised them yet. |
| Cloudflare API credentials | **Configured, missing KV permission** | The ignored `.secrets.env` contains one account-owned `CLOUDFLARE_API_TOKEN` plus `CLOUDFLARE_ACCOUNT_ID`. Token verification, account read, and Workers script listing succeeded without printing credential values, while the OAuth KV namespace listing returned Cloudflare authentication error `10000`. The current token must gain `Workers KV Storage: Edit` before deployment. |
| Staging deployment and health | **Configuration required** | The previously discussed Workers origin returned HTTP 404, and the Cloudflare service lookup also returned 404. `wrangler.jsonc` still contains deployment placeholders, while the runner repository has no `TASK_CONTROL_PLANE_URL` variable. This is missing deployment configuration, not a code failure. |
| End-to-end ChatGPT OAuth, MCP task dispatch, callback, executor result, and cancellation | **Not tested** | Local contract tests do not prove the deployed cross-system flow. |

The staging Worker is not currently deployed. No conclusion is recorded yet
about the end-to-end task lifecycle; it requires deployment and external
validation.
