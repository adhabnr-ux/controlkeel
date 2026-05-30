/**
 * ControlKeel SDK integration tests.
 *
 * Uses Node.js built-in test runner (node:test) + mock HTTP server (node:http).
 * Zero new dependencies. Run with: npm test
 *
 * Each test starts its own HTTP server on a random port, runs assertions,
 * then closes the server. No network calls leave localhost.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { ControlKeelClient } from "../dist/index.js";

// ── Helpers ──────────────────────────────────────────────────────────

/** Start an HTTP server, wait for it to be ready, return it + its base URL. */
function startServer(handler) {
  return new Promise((resolve) => {
    const server = http.createServer(handler);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({ server, baseUrl: `http://127.0.0.1:${port}` });
    });
  });
}

function stopServer(server) {
  return new Promise((resolve) => server.close(resolve));
}

function jsonResponse(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

// ── Sync push ─────────────────────────────────────────────────────────

test("syncPush — 200 returns accepted/inserted/updated", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 200, { accepted: 3, inserted: 1, updated: 2, skipped: 0, no_change: 0, conflicts: 0 });
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const result = await client.syncPush("ws_1", []);
  assert.equal(result.accepted, 3);
  assert.equal(result.inserted, 1);
  await stopServer(server);
});

test("syncPush — 401 throws ControlKeelError with status 401", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 401, { error: "unauthorized" });
  });
  const client = new ControlKeelClient({ baseUrl, token: "bad", maxRetries: 0 });
  await assert.rejects(
    () => client.syncPush("ws_1", []),
    (err) => {
      assert.equal(err.status, 401);
      return true;
    },
  );
  await stopServer(server);
});

test("syncPush — 429 with Retry-After:0 retries once and succeeds", async () => {
  let calls = 0;
  const { server, baseUrl } = await startServer((_req, res) => {
    calls++;
    if (calls === 1) {
      res.writeHead(429, { "content-type": "application/json", "retry-after": "0" });
      res.end(JSON.stringify({ error: "rate_limited", retry_after: 0 }));
    } else {
      jsonResponse(res, 200, { accepted: 1, inserted: 1, updated: 0, skipped: 0, no_change: 0, conflicts: 0 });
    }
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok", maxRetries: 1 });
  const result = await client.syncPush("ws_1", []);
  assert.equal(result.accepted, 1);
  assert.equal(calls, 2);
  await stopServer(server);
});

test("syncPush — 503 retries then throws if maxRetries exhausted", async () => {
  let calls = 0;
  const { server, baseUrl } = await startServer((_req, res) => {
    calls++;
    res.writeHead(503, { "content-type": "application/json", "retry-after": "0" });
    res.end(JSON.stringify({ error: "unavailable" }));
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok", maxRetries: 1 });
  await assert.rejects(() => client.syncPush("ws_1", []), { status: 503 });
  assert.equal(calls, 2); // initial + 1 retry
  await stopServer(server);
});

// ── Sync pull ─────────────────────────────────────────────────────────

test("syncPull — 200 returns records array", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 200, { records: [{ kind: "finding", external_id: "f_1" }], total: 1 });
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const result = await client.syncPull("ws_1", "1970-01-01T00:00:00Z");
  assert.equal(result.records.length, 1);
  assert.equal(result.records[0].kind, "finding");
  await stopServer(server);
});

// ── Workspace registration ─────────────────────────────────────────────

test("registerWorkspace — malformed body returns 400 (endpoint mounted)", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 400, { error: "malformed" });
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok", maxRetries: 0 });
  await assert.rejects(() => client.registerWorkspace({}), { status: 400 });
  await stopServer(server);
});

// ── Service accounts ──────────────────────────────────────────────────

test("listServiceAccounts — 200 returns accounts array", async () => {
  const accounts = [{ id: 1, name: "ci", workspace_id: 42, status: "active" }];
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 200, accounts);
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const result = await client.listServiceAccounts("42");
  assert.equal(result.length, 1);
  assert.equal(result[0].name, "ci");
  await stopServer(server);
});

test("createServiceAccount — 201 returns service_account + token", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    res.writeHead(201, { "content-type": "application/json" });
    res.end(JSON.stringify({ service_account: { id: 2, name: "deploy", workspace_id: 42 }, token: "raw_tok" }));
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const result = await client.createServiceAccount("42", { name: "deploy", scopes: ["sync:write"] });
  assert.equal(result.token, "raw_tok");
  await stopServer(server);
});

// ── Webhooks ──────────────────────────────────────────────────────────

test("listWebhooks — returns array", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 200, [{ id: 1, name: "slack", url: "https://hooks.slack.com/x" }]);
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const hooks = await client.listWebhooks("42");
  assert.equal(hooks.length, 1);
  await stopServer(server);
});

// ── Tool policy ───────────────────────────────────────────────────────

test("getToolPolicy — returns mode and tools", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    jsonResponse(res, 200, { workspace_id: 42, mode: "inherit", tools: [] });
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const policy = await client.getToolPolicy("42");
  assert.equal(policy.mode, "inherit");
  await stopServer(server);
});

test("setToolPolicy — PUT body forwarded, returns updated policy", async () => {
  let receivedBody = "";
  const { server, baseUrl } = await startServer((req, res) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => {
      receivedBody = data;
      jsonResponse(res, 200, { workspace_id: 42, mode: "allowlist", tools: ["ck_validate"] });
    });
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok" });
  const result = await client.setToolPolicy("42", { mode: "allowlist", tools: ["ck_validate"] });
  assert.equal(result.mode, "allowlist");
  const body = JSON.parse(receivedBody);
  assert.deepEqual(body.tools, ["ck_validate"]);
  await stopServer(server);
});

// ── Error type ────────────────────────────────────────────────────────

test("ControlKeelError carries status, message, and retryAfter", async () => {
  const { server, baseUrl } = await startServer((_req, res) => {
    res.writeHead(429, { "content-type": "application/json", "retry-after": "5" });
    res.end(JSON.stringify({ error: "rate_limited", retry_after: 5 }));
  });
  const client = new ControlKeelClient({ baseUrl, token: "tok", maxRetries: 0 });
  await assert.rejects(
    () => client.syncPush("ws_1", []),
    (err) => {
      assert.equal(err.status, 429);
      assert.equal(err.retryAfter, 5);
      assert.ok(err.message.length > 0);
      return true;
    },
  );
  await stopServer(server);
});
