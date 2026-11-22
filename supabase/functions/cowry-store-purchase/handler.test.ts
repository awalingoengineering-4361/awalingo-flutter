import assert from "node:assert/strict";
import { test } from "node:test";
import {
  createStorePurchaseHandler,
  type StorePurchaseDependencies,
  type VerifiedStorePurchase,
} from "./handler.ts";

async function verified(
  promise: Promise<VerifiedStorePurchase | Response>,
): Promise<VerifiedStorePurchase> {
  const value = await promise;
  assert.ok(!(value instanceof Response));
  return value;
}
const owner = "00000000-0000-0000-0000-000000000001";
function fixture() {
  let credits = 0;
  const credited = new Set<string>();
  const deps: StorePurchaseDependencies = {
    authenticate: async () => ({ id: owner }),
    deletionState: async () => "active",
    configured: () => true,
    testUserAllowed: () => false,
    checkoutAllowed: () => true,
    verify: async () => ({
      txRef: "play-one",
      providerRef: "order-one",
      accountId: owner,
      status: "SUCCESSFUL",
      amount: 0,
      currency: "",
      quantity: 1,
      testPurchase: false,
      raw: {},
    }),
    fulfill: async (purchase) => {
      const duplicate = credited.has(purchase.txRef);
      if (!duplicate) {
        credited.add(purchase.txRef);
        credits++;
      }
      return new Response(
        JSON.stringify({ success: true, alreadyProcessed: duplicate }),
        { status: 200 },
      );
    },
  };
  const request = (extra: Record<string, unknown> = {}) =>
    createStorePurchaseHandler(deps)(
      new Request("https://example.invalid", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          Authorization: "Bearer fixture",
        },
        body: JSON.stringify({
          provider: "GOOGLE_PLAY",
          productId: "cowries_copper_50",
          purchaseToken: "token",
          ...extra,
        }),
      }),
    );
  return { deps, request, credits: () => credits };
}

test("eligibility does not fulfill a purchase or require a receipt", async () => {
  const f = fixture();
  assert.equal(
    (await (await f.request({ action: "eligibility" })).json()).eligible,
    true,
  );
  assert.equal(f.credits(), 0);
});
test("unauthenticated checkout is denied", async () => {
  const f = fixture();
  f.deps.authenticate = async () => null;
  assert.equal((await f.request()).status, 401);
  assert.equal(f.credits(), 0);
});
for (const state of ["deleting", "unavailable"] as const) {
  test(`${state} account cannot start or fulfill checkout`, async () => {
    const f = fixture();
    f.deps.deletionState = async () => state;
    assert.equal(
      (await f.request({ action: "eligibility" })).status,
      state === "deleting" ? 403 : 503,
    );
    assert.equal((await f.request()).status, state === "deleting" ? 403 : 503);
    assert.equal(f.credits(), 0);
  });
}
test("unconfigured store fails before checkout", async () => {
  const f = fixture();
  f.deps.configured = () => false;
  assert.equal((await f.request({ action: "eligibility" })).status, 503);
});
for (const accountId of [undefined, "someone-else"]) {
  test(`receipt owned by ${accountId ?? "nobody"} cannot credit this account`, async () => {
    const f = fixture();
    const verify = f.deps.verify;
    f.deps.verify = async (...args) => ({
      ...await verified(verify(...args)),
      accountId,
    });
    assert.equal((await f.request()).status, 403);
    assert.equal(f.credits(), 0);
  });
}
test("a sandbox/license-test purchase needs explicit server-side permission", async () => {
  const f = fixture();
  const verify = f.deps.verify;
  f.deps.verify = async (...args) => ({
    ...await verified(verify(...args)),
    testPurchase: true,
  });
  assert.equal((await f.request()).status, 403);
  assert.equal(f.credits(), 0);
  f.deps.testUserAllowed = () => true;
  assert.equal((await f.request()).status, 200);
  assert.equal(f.credits(), 1);
});
test("multi-quantity purchase is not silently undercredited", async () => {
  const f = fixture();
  const verify = f.deps.verify;
  f.deps.verify = async (...args) => ({
    ...await verified(verify(...args)),
    quantity: 2,
  });
  assert.equal((await f.request()).status, 409);
  assert.equal(f.credits(), 0);
});
test("pending and revoked purchases never reach the wallet", async () => {
  for (const status of ["PENDING", "FAILED"] as const) {
    const f = fixture();
    const verify = f.deps.verify;
    f.deps.verify = async (...args) => ({
      ...await verified(verify(...args)),
      status,
    });
    assert.equal((await f.request()).status, status === "PENDING" ? 202 : 400);
    assert.equal(f.credits(), 0);
  }
});
test("store outages are retryable and do not credit", async () => {
  const f = fixture();
  f.deps.verify = async () => {
    throw new Error("offline");
  };
  const response = await f.request();
  assert.equal(response.status, 502);
  assert.equal((await response.json()).retryable, true);
  assert.equal(f.credits(), 0);
});
test("duplicate receipts reuse identity; a second purchase has a new identity", async () => {
  const f = fixture();
  assert.equal((await f.request()).status, 200);
  assert.equal((await (await f.request()).json()).alreadyProcessed, true);
  assert.equal(f.credits(), 1);
  const verify = f.deps.verify;
  f.deps.verify = async (...args) => ({
    ...await verified(verify(...args)),
    txRef: "play-two",
  });
  assert.equal((await f.request()).status, 200);
  assert.equal(f.credits(), 2);
});
test("unknown action or product never opens checkout", async () => {
  const f = fixture();
  assert.equal((await f.request({ action: "unexpected" })).status, 400);
  assert.equal(
    (await f.request({ action: "eligibility", productId: "unknown" })).status,
    400,
  );
});

test("testing rollout blocks non-testers before the payment sheet", async () => {
  const f = fixture();
  f.deps.checkoutAllowed = () => false;
  assert.equal((await f.request({ action: "eligibility" })).status, 403);
  assert.equal(f.credits(), 0);
  // Turning off new sales must still deliver a previously paid live receipt.
  assert.equal((await f.request()).status, 200);
});

test("deletion accepted during store verification is rechecked before fulfillment", async () => {
  const f = fixture();
  let deleting = false;
  const verify = f.deps.verify;
  f.deps.deletionState = async () => deleting ? "deleting" : "active";
  f.deps.verify = async (...args) => {
    deleting = true;
    return await verify(...args);
  };
  assert.equal((await f.request()).status, 403);
  assert.equal(f.credits(), 0);
});
