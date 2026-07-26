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
| Complete local Node test suite | **Passed** | `node --test tests/*.test.js`: 33 passed and 0 failed. |
| Installation auto-resolution behavior | **Passed in code-level test** | The production-edge test observes repository installation lookup followed by installation-token creation and workflow dispatch. Deployment configuration contains no manual installation ID. |
| GitHub App installation | **Passed** | An App JWT authenticated `GET /repos/weavertech-group/runner/installation`. The installation covers all repositories and reports `Actions`, `Contents`, and `Pull requests: write` plus `Metadata: read`. The ID and JWT were not printed or persisted. |
| Runner GitHub App credentials | **Passed** | Production run `30196554687` created a target-repository installation token and checked out `weavertech-group/runner` successfully. The workflow uses `RUNNER_GITHUB_APP_ID` and `RUNNER_GITHUB_APP_PRIVATE_KEY` because GitHub rejects custom secret names beginning with `GITHUB_`; no credential value was recorded. |
| Codex executor credentials | **Configured, not exercised** | `CODEX_API_KEY` and `CODEX_RESPONSES_API_ENDPOINT` exist as runner repository secrets. They were uploaded from the local provider configuration through stdin without printing their values. No workflow run has exercised them yet. |
| Cloudflare API credentials | **Passed for the current deployment boundary** | The ignored `.secrets.env` contains one account-owned `CLOUDFLARE_API_TOKEN` plus `CLOUDFLARE_ACCOUNT_ID`. Token verification, account read, Workers script listing, and KV namespace listing all returned HTTP 200 without printing credential values. Creating the production OAuth KV namespace proved the required KV write permission. |
| Staging deployment and health | **Passed** | Worker version `fec3b8fb-a3f3-4613-8658-612744709609` is deployed at the configured Workers.dev origin with the OAuth KV binding and task Durable Object. `/health` returned exact body `ok`; OAuth metadata endpoints returned 200; unauthenticated `/mcp` returned 401 with a bearer challenge; invalid authorization and callback requests returned safe 400 responses. The runner repository `TASK_CONTROL_PLANE_URL` variable exactly matches the Worker origin. |
| Deployed OAuth authorization and MCP authentication | **Passed** | A public PKCE client completed interactive GitHub authorization, Worker callback, OAuth grant persistence, authorization-code token exchange, refresh-token issuance, and authenticated MCP `initialize`. The validation recorded only boolean/result summaries and did not print or persist codes or tokens. The original failure was a 403 HTML response from GitHub `GET /user` without the required `User-Agent`, followed by an unhandled JSON parse exception; the deployed fix validates the profile response, uses the delimiter-safe `github-<id>` subject, and applies unified GitHub REST headers. |
| MCP task dispatch and runner checkout | **Passed** | `submit_task` created `task_b680badb-4a1d-42bd-97e7-4f20b19626d5`; production run `30196554687` dispatched from `main`, resolved the target installation, created a token, and checked out the target repository. |
| Runner callback, executor result, and cancellation | **Partially tested; blocked before callback** | Production run `30196554687` failed in `Report running` before making a network request because the local Node action rewrote hyphens in GitHub's `INPUT_CONTROL-PLANE-URL` and `INPUT_TASK-ID` environment keys. The action therefore constructed `/internal/tasks//events`; the regression test now exercises the real process boundary and the minimal fix preserves hyphens. A new production task is required to validate OIDC callback, executor, result, and cancellation. |

The staging Worker, OAuth-to-MCP authentication path, task dispatch, App
credentials, and runner checkout are externally validated. The next acceptance
boundary starts at the corrected OIDC callback.
