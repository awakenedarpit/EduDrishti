import assert from "node:assert/strict";
import test from "node:test";
import { createServiceDependencies } from "./backend.ts";

const values: Record<string, string> = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "sb_publishable_public-example" }),
  GEMINI_API_KEY: "server-test-key",
};

function envWith(extra: Record<string, string>) {
  const all = { ...values, ...extra };
  return (name: string) => all[name];
}

test("new Supabase secret keys use apikey but are never sent as Authorization Bearer", async () => {
  const receivedHeaders: Headers[] = [];
  const deps = createServiceDependencies(envWith({
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: "sb_secret_private-example" }),
  }), async (_input, init) => {
    receivedHeaders.push(new Headers(init?.headers));
    return new Response("true", { status: 200, headers: { "content-type": "application/json" } });
  });
  assert.equal(await deps.consumeRateLimit("55555555-5555-4555-8555-555555555555", "explanation"), true);
  assert.equal(receivedHeaders[0]?.get("apikey"), "sb_secret_private-example");
  assert.equal(receivedHeaders[0]?.get("authorization"), null);
});

test("legacy service-role JWTs remain supported as an Authorization bearer", async () => {
  const receivedHeaders: Headers[] = [];
  const legacyKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature";
  const deps = createServiceDependencies(envWith({ SUPABASE_SERVICE_ROLE_KEY: legacyKey }), async (_input, init) => {
    receivedHeaders.push(new Headers(init?.headers));
    return new Response("true", { status: 200, headers: { "content-type": "application/json" } });
  });
  assert.equal(await deps.consumeRateLimit("55555555-5555-4555-8555-555555555555", "explanation"), true);
  assert.equal(receivedHeaders[0]?.get("apikey"), legacyKey);
  assert.equal(receivedHeaders[0]?.get("authorization"), `Bearer ${legacyKey}`);
});
