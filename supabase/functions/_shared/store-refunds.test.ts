import assert from "node:assert/strict";
import { test } from "node:test";
import { reconcileVoidedPurchases } from "./store-refunds.ts";

test("refund reconciliation uses verified tokens, follows pages and safely repeats", async () => {
  let balance = 75;
  const reversed = new Set<string>();
  const pages: (string | undefined)[] = [];
  const run = () =>
    reconcileVoidedPurchases({
      list: async (page) => {
        pages.push(page);
        return page
          ? { purchases: [{ purchaseToken: "second" }] }
          : { purchases: [{ purchaseToken: "first" }], nextPage: "page-two" };
      },
      reverse: async (txRef) => {
        if (!reversed.has(txRef)) {
          reversed.add(txRef);
          balance -= 50;
        }
      },
    });
  assert.deepEqual(await run(), { processed: 2, pages: 2 });
  assert.equal(balance, -25); // Already spent cowries stay represented as a debt.
  await run();
  assert.equal(balance, -25);
  assert.deepEqual(pages, [undefined, "page-two", undefined, "page-two"]);
  assert.deepEqual([...reversed], [
    "play-a7937b64b8caa58f03721bb6bacf5c78cb235feb",
    "play-16367aacb67a4a017c8da8ab95682ccb39086378",
  ]);
});

test("an incomplete provider response or database failure fails the job", async () => {
  await assert.rejects(() =>
    reconcileVoidedPurchases({
      list: async () => ({ purchases: [{ purchaseToken: "" }] }),
      reverse: async () => {},
    })
  );
  await assert.rejects(() =>
    reconcileVoidedPurchases({
      list: async () => ({ purchases: [{ purchaseToken: "valid" }] }),
      reverse: async () => {
        throw new Error("db unavailable");
      },
    })
  );
});

test("pagination loops fail visibly instead of claiming a complete scan", async () => {
  await assert.rejects(() =>
    reconcileVoidedPurchases({
      list: async () => ({ purchases: [], nextPage: "loop" }),
      reverse: async () => {},
    })
  );
});

test("one failed reversal does not block other customers or later pages", async () => {
  const processed: string[] = [];
  await assert.rejects(() =>
    reconcileVoidedPurchases({
      list: async (page) =>
        page ? { purchases: [{ purchaseToken: "last-customer" }] } : {
          purchases: [{ purchaseToken: "stuck-deletion" }, {
            purchaseToken: "other-customer",
          }],
          nextPage: "next",
        },
      reverse: async (ref) => {
        if (
          ref === "play-cbbe5b8e72da421f07ca7826aff578e7e7f2b915"
        ) throw new Error("pending deletion");
        processed.push(ref);
      },
    })
  );
  assert.equal(processed.length, 2);
});
