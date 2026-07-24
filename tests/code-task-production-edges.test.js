import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test, { afterEach } from "node:test";

import { authorizeRepository } from "../apps/chatgpt-app/src/github.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("pull_request mode requires ref to resolve as a branch", async () => {
  const requests = [];
  globalThis.fetch = async (url) => {
    requests.push(String(url));
    if (requests.length === 1) {
      return new Response(JSON.stringify({ permissions: { push: true } }), { status: 200 });
    }
    return new Response(JSON.stringify({ name: "feature/task" }), { status: 200 });
  };

  await authorizeRepository(
    "owner/project",
    { githubAccessToken: "token" },
    "pull_request",
    "feature/task",
  );

  assert.deepEqual(requests, [
    "https://api.github.com/repos/owner/project",
    "https://api.github.com/repos/owner/project/branches/feature%2Ftask",
  ]);
});

test("pull_request mode rejects tags and commits that are not branches", async () => {
  let requestCount = 0;
  globalThis.fetch = async () => {
    requestCount += 1;
    if (requestCount === 1) {
      return new Response(JSON.stringify({ permissions: { push: true } }), { status: 200 });
    }
    return new Response("not found", { status: 404 });
  };

  await assert.rejects(
    authorizeRepository(
      "owner/project",
      { githubAccessToken: "token" },
      "pull_request",
      "deadbeef",
    ),
    /requires ref to name an accessible branch/,
  );
});

test("edit mode does not require a branch-only ref", async () => {
  const requests = [];
  globalThis.fetch = async (url) => {
    requests.push(String(url));
    return new Response(JSON.stringify({ permissions: { push: true } }), { status: 200 });
  };

  await authorizeRepository(
    "owner/project",
    { githubAccessToken: "token" },
    "edit",
    "deadbeef",
  );

  assert.deepEqual(requests, ["https://api.github.com/repos/owner/project"]);
});

test("workflow skips delivery steps when an executor produces no changes", async () => {
  const workflow = await readFile(
    new URL("../.github/workflows/execute-task.yml", import.meta.url),
    "utf8",
  );

  assert.match(workflow, /- name: Detect task changes\n\s+id: changes/);
  assert.match(
    workflow,
    /if: \$\{\{ inputs\.mode != 'analyze' && steps\.changes\.outputs\.changed == 'true' \}\}/,
  );
  assert.match(
    workflow,
    /if: \$\{\{ inputs\.mode == 'pull_request' && steps\.changes\.outputs\.changed == 'true' \}\}/,
  );
  assert.match(workflow, /summary="No changes produced\."/);
});

test("submit_task records a failed state when workflow dispatch fails", async () => {
  const source = await readFile(
    new URL("../apps/chatgpt-app/src/mcp.js", import.meta.url),
    "utf8",
  );

  assert.match(source, /await dispatchWorkflow\(env, task\);/);
  assert.match(source, /status: "failed",\n\s+error: "workflow dispatch failed"/);
});
