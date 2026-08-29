const test = require("node:test");
const assert = require("node:assert/strict");

process.env.ALLOWED_ORIGINS = "https://nyxra-ai-shamii.web.app";
process.env.VERCEL = "1";
const app = require("../server");

let server;
let baseUrl;

test.before(async () => {
  server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => error ? reject(error) : resolve()),
  );
});

test("health endpoint is available and hardened", async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-powered-by"), null);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});

test("chat rejects an empty request", async () => {
  const response = await fetch(`${baseUrl}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });
  assert.equal(response.status, 400);
});

test("CORS permits the app and rejects an untrusted website", async () => {
  const allowed = await fetch(`${baseUrl}/api/chat`, {
    method: "OPTIONS",
    headers: {
      origin: "https://nyxra-ai-shamii.web.app",
      "access-control-request-method": "POST",
    },
  });
  assert.equal(allowed.status, 204);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://nyxra-ai-shamii.web.app",
  );

  const rejected = await fetch(`${baseUrl}/api/chat`, {
    method: "OPTIONS",
    headers: {
      origin: "https://untrusted.example",
      "access-control-request-method": "POST",
    },
  });
  assert.equal(rejected.status, 403);
});

test("API rate limiter blocks repeated requests", async () => {
  let response;
  for (let index = 0; index < 41; index += 1) {
    response = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-forwarded-for": "203.0.113.25",
      },
      body: JSON.stringify({}),
    });
  }
  assert.equal(response.status, 429);
  assert.ok(Number(response.headers.get("retry-after")) > 0);
});
