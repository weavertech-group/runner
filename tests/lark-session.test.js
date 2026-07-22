const assert = require("node:assert/strict");
const { mkdir, mkdtemp, readFile, rm, writeFile } = require("node:fs/promises");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const test = require("node:test");

const { cleanup } = require("../.github/actions/lark-session/cleanup.js");
const { run } = require("../.github/actions/lark-session/index.js");

function response(body) {
  return { json: async () => body };
}

async function actionEnvironment(status) {
  const directory = await mkdtemp(join(tmpdir(), "lark-session-"));
  const environmentFile = join(directory, "github-env");
  const stateFile = join(directory, "github-state");
  await writeFile(environmentFile, "");
  await writeFile(stateFile, "");

  return {
    directory,
    environment: {
      GITHUB_ENV: environmentFile,
      GITHUB_STATE: stateFile,
      HOME: directory,
      GITHUB_REPOSITORY: "weavertech-group/runner",
      GITHUB_RUN_ID: "123456",
      GITHUB_RUN_ATTEMPT: "2",
      GITHUB_SERVER_URL: "https://github.com",
      INPUT_STATUS: status,
      LARK_APP_ID: "cli_test",
      LARK_APP_SECRET: "secret",
      LARK_CHAT_NAME: "Runner sessions",
      SESSION_SSH_ONLINE: "false",
      SESSION_TARGET_ID: "repo-01",
    },
  };
}

test("starting creates one card in the exact chat and saves its message id", async () => {
  const context = await actionEnvironment("starting");
  const requests = [];
  const fetch = async (url, options = {}) => {
    requests.push({ url: String(url), options });
    if (requests.length === 1) {
      return response({ code: 0, tenant_access_token: "tenant-token" });
    }
    if (requests.length === 2) {
      return response({
        code: 0,
        data: {
          has_more: true,
          page_token: "next page",
          items: [{ chat_id: "oc_other", name: "Other" }],
        },
      });
    }
    if (requests.length === 3) {
      return response({
        code: 0,
        data: {
          has_more: false,
          items: [{ chat_id: "oc_runner", name: "Runner sessions" }],
        },
      });
    }
    return response({ code: 0, data: { message_id: "om_session" } });
  };

  await run(context.environment, fetch);

  assert.equal(requests[1].url, "https://open.larksuite.com/open-apis/im/v1/chats?page_size=100");
  assert.equal(
    requests[2].url,
    "https://open.larksuite.com/open-apis/im/v1/chats?page_size=100&page_token=next+page",
  );
  assert.equal(
    requests[3].url,
    "https://open.larksuite.com/open-apis/im/v1/messages?receive_id_type=chat_id",
  );
  const sent = JSON.parse(requests[3].options.body);
  assert.equal(sent.receive_id, "oc_runner");
  assert.equal(sent.msg_type, "interactive");
  assert.match(JSON.parse(sent.content).body.elements[0].content, /Starting/);
  assert.equal(await readFile(context.environment.GITHUB_ENV, "utf8"), "LARK_MESSAGE_ID=om_session\n");
  assert.equal(await readFile(context.environment.GITHUB_STATE, "utf8"), "message_id=om_session\n");
  await rm(context.directory, { recursive: true });
});

test("online updates the existing card without registering another cleanup", async () => {
  const context = await actionEnvironment("online");
  context.environment.LARK_MESSAGE_ID = "om_session";
  const sessionDirectory = join(context.directory, "private-runner-session", "t3code");
  await mkdir(sessionDirectory, { recursive: true });
  await writeFile(join(sessionDirectory, "t3-url"), "https://runner.trycloudflare.com\n");
  const requests = [];
  const fetch = async (url, options = {}) => {
    requests.push({ url: String(url), options });
    return response(requests.length === 1
      ? { code: 0, tenant_access_token: "tenant-token" }
      : { code: 0 });
  };

  await run(context.environment, fetch);

  assert.equal(
    requests[1].url,
    "https://open.larksuite.com/open-apis/im/v1/messages/om_session",
  );
  assert.equal(requests[1].options.method, "PATCH");
  const updated = JSON.parse(requests[1].options.body);
  const markdown = JSON.parse(updated.content).body.elements[0].content;
  assert.match(markdown, /Online/);
  assert.match(markdown, /https:\/\/runner[.]trycloudflare[.]com/);
  assert.equal(await readFile(context.environment.GITHUB_STATE, "utf8"), "");
  await cleanup(context.environment, fetch);
  assert.equal(requests.length, 2);
  await rm(context.directory, { recursive: true });
});

test("post updates the owning card to Offline and omits temporary access", async () => {
  const context = await actionEnvironment("starting");
  context.environment.STATE_message_id = "om_session";
  context.environment.SESSION_T3_URL = "https://runner.trycloudflare.com";
  const requests = [];
  const fetch = async (url, options = {}) => {
    requests.push({ url: String(url), options });
    return response(requests.length === 1
      ? { code: 0, tenant_access_token: "tenant-token" }
      : { code: 0 });
  };

  await cleanup(context.environment, fetch);

  assert.equal(
    requests[1].url,
    "https://open.larksuite.com/open-apis/im/v1/messages/om_session",
  );
  const updated = JSON.parse(requests[1].options.body);
  const markdown = JSON.parse(updated.content).body.elements[0].content;
  assert.match(markdown, /Offline/);
  assert.doesNotMatch(markdown, /trycloudflare/);
  await rm(context.directory, { recursive: true });
});
