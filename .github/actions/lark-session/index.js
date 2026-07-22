const { appendFile, readFile } = require("node:fs/promises");
const { join } = require("node:path");

const API = "https://open.larksuite.com/open-apis";

function card(status, environment) {
  const runUrl = `${environment.GITHUB_SERVER_URL}/${environment.GITHUB_REPOSITORY}/actions/runs/${environment.GITHUB_RUN_ID}`;
  const content = [
    `**Status:** ${status}`,
    `**Target:** ${environment.SESSION_TARGET_ID}`,
    ...(status === "Online" ? [`**T3:** ${environment.SESSION_T3_URL}`] : []),
    ...(status === "Online" ? [`**SSH:** ${environment.SESSION_SSH_ONLINE}`] : []),
    `**Run:** [${environment.GITHUB_RUN_ID} · attempt ${environment.GITHUB_RUN_ATTEMPT}](${runUrl})`,
  ].join("\n");

  return {
    schema: "2.0",
    config: { update_multi: true },
    header: {
      title: { tag: "plain_text", content: "Private T3 session" },
      template: status === "Online" ? "green" : status === "Offline" ? "grey" : "blue",
    },
    body: { elements: [{ tag: "markdown", content }] },
  };
}

async function token(environment, fetchImpl) {
  const response = await fetchImpl(`${API}/auth/v3/tenant_access_token/internal`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({
      app_id: environment.LARK_APP_ID,
      app_secret: environment.LARK_APP_SECRET,
    }),
  });
  return (await response.json()).tenant_access_token;
}

async function run(environment = process.env, fetchImpl = fetch) {
  const accessToken = await token(environment, fetchImpl);
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json; charset=utf-8",
  };
  if (environment.INPUT_STATUS !== "starting") {
    const status = environment.INPUT_STATUS === "online" ? "Online" : "Offline";
    const cardEnvironment = status === "Online"
      ? {
          ...environment,
          SESSION_T3_URL: environment.SESSION_T3_URL ?? (await readFile(
            join(environment.HOME, "private-runner-session", "t3code", "t3-url"),
            "utf8",
          )).trim(),
        }
      : environment;
    await fetchImpl(`${API}/im/v1/messages/${environment.LARK_MESSAGE_ID}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({ content: JSON.stringify(card(status, cardEnvironment)) }),
    });
    return;
  }

  let chat;
  let pageToken;
  do {
    const query = new URLSearchParams({ page_size: "100" });
    if (pageToken) {
      query.set("page_token", pageToken);
    }
    const chatsResponse = await fetchImpl(`${API}/im/v1/chats?${query}`, { headers });
    const { data } = await chatsResponse.json();
    chat = data.items.find(({ name }) => name === environment.LARK_CHAT_NAME);
    pageToken = data.has_more ? data.page_token : undefined;
  } while (!chat && pageToken);
  const messageResponse = await fetchImpl(
    `${API}/im/v1/messages?receive_id_type=chat_id`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        receive_id: chat.chat_id,
        msg_type: "interactive",
        content: JSON.stringify(card("Starting", environment)),
      }),
    },
  );
  const messageId = (await messageResponse.json()).data.message_id;
  await appendFile(environment.GITHUB_ENV, `LARK_MESSAGE_ID=${messageId}\n`);
  await appendFile(environment.GITHUB_STATE, `message_id=${messageId}\n`);
}

module.exports = { run };

if (require.main === module) {
  run();
}
