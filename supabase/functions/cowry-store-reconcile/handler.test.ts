import assert from "node:assert/strict";
import { test } from "node:test";
import { createReconcileHandler } from "./handler.ts";

const secret = "fixture-32-character-server-secret-only";
test("only the scheduled server credential can run refund reconciliation", async () => {
  let runs = 0;
  const handler = createReconcileHandler(() => secret, async () => {
    runs++;
    return { processed: 0, pages: 1 };
  });
  for (const token of ["", "Bearer public-anon-key", "Bearer user-jwt"]) {
    const response = await handler(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { Authorization: token },
      }),
    );
    assert.equal(response.status, 401);
  }
  assert.equal(runs, 0);
  assert.equal(
    (await handler(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { Authorization: `Bearer ${secret}` },
        body: '{"purchaseToken":"untrusted"}',
      }),
    )).status,
    200,
  );
  assert.equal(runs, 1);
});
test("missing server configuration or failed reconciliation never reports success", async () => {
  const request = () =>
    new Request("https://example.invalid", {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}` },
    });
  assert.equal(
    (await createReconcileHandler(() => "", async () => ({}))(request()))
      .status,
    503,
  );
  assert.equal(
    (await createReconcileHandler(() => secret, async () => {
      throw new Error("provider down");
    })(request())).status,
    503,
  );
});
