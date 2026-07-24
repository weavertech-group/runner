# ChatGPT code-task app

The repository now contains a separate Cloudflare Worker control plane under
`apps/chatgpt-app`. Its stable public endpoint is the Worker origin followed by
`/mcp`; the temporary GitHub runner remains the execution plane. The existing
Private T3 Session workflow is unchanged and can still be used independently.

## Request flow

1. ChatGPT authenticates to the Worker through OAuth 2.1 + PKCE. The Worker
   uses the configured GitHub OAuth application for user identity and keeps the
   GitHub user token and granted tool scopes encrypted in the OAuth provider
   grant properties; every tool checks its required scopes again.
2. `submit_task` checks that the user can access the requested repository,
   stores the complete prompt in a per-task Durable Object, and dispatches
   `.github/workflows/execute-task.yml` in this repository through a GitHub App.
3. The workflow receives only `task_id`, `repo`, `ref`, `executor`, and `mode`.
   It obtains a short-lived GitHub Actions OIDC token, fetches the private
   prompt from `/internal/tasks/<task_id>`, and reports lifecycle events back to
   the same task object.
4. `get_task`, `get_task_result`, and `cancel_task` expose only the task's safe
   public fields. Prompt text, OAuth properties, and callback credentials never
   appear in MCP structured content.

The public tools are:

| Tool | Purpose | Side effect |
| --- | --- | --- |
| `submit_task` | Queue a code task | Starts a GitHub Actions run |
| `get_task` | Read current status | None |
| `cancel_task` | Request cancellation | Cancels a GitHub run when its run ID is known |
| `get_task_result` | Read summary, commit, or PR | None |

`executor` currently accepts `codex`, `claude`, and `grok`. Each executor has
an independent workflow step and uses its current official installer. Grok
Build requires the `XAI_API_KEY` secret. `mode=analyze` leaves the checkout
unchanged; `edit` pushes a task branch; `pull_request` also creates a PR.

## Cloudflare setup

From `apps/chatgpt-app`, create the OAuth KV namespace and replace every
`REPLACE_WITH_*` value in `wrangler.jsonc` with the deployed Worker hostname,
the runner-repository GitHub App installation ID, and the GitHub OAuth client
ID:

```bash
npx wrangler kv namespace create OAUTH_KV
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_APP_PRIVATE_KEY
npx wrangler secret put GITHUB_OAUTH_CLIENT_SECRET
npx wrangler deploy
```

Set the GitHub OAuth application's callback URL as:

```text
https://runner.example.com/github/callback
```

Set the `TASK_CONTROL_PLANE_URL` repository variable in the runner repository
to the Worker origin, for example `https://runner.example.com`. The workflow
uses that value as the OIDC audience and callback base URL.

The Worker `TASK_CONTROL_PLANE_URL` value and the repository variable must be
byte-for-byte identical. Do not put the OAuth client secret, GitHub App private
key, task prompt, or OIDC token in `wrangler.jsonc`, workflow inputs, MCP
structured content, logs, summaries, or artifacts.

The GitHub App needs `Actions: write` on the runner repository so the Worker
can dispatch the workflow. The same App must be installed on target
repositories with the contents and pull-request permissions required by the
selected task mode. The workflow also needs the App ID and private key as
runner-repository secrets. Put `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and
`XAI_API_KEY` there for the executors you enable; these credentials are scoped
to their individual workflow steps and are not needed by the Worker.

The OAuth provider's consent page uses GitHub OAuth scopes `read:user repo` by
default. Use a separate GitHub OAuth application for this service and review
its organization access policy before connecting private repositories.
The OAuth token is used only to verify the user's repository access; the
GitHub App installation token is the credential used by the runner workflow.
Replacing this MVP check with GitHub App user-to-server authorization is a
future least-privilege refinement, not a second execution credential.

## Local checks

```bash
node --test tests/task-contract.test.js
npm --prefix apps/chatgpt-app run typecheck
npm --prefix apps/chatgpt-app run deploy -- --dry-run
```

The dry run validates the Worker bundle and Durable Object binding without
requiring a deployed KV namespace. A real deployment still requires replacing
the KV and Worker-variable placeholders and setting the secrets above.
