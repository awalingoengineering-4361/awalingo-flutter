// Credits cowries for an App Store or Google Play in-app purchase made in
// the iOS/Android app. Every request verifies the Supabase access token
// with Auth.getUser before any privileged database operation.
//
// The app only says which transaction it saw; the transaction itself is
// looked up with Apple/Google before anything is credited. Each store
// transaction maps to one cowry_payments row (txRef is unique), and
// credit_cowry_payment only credits a PENDING row once, so the app can
// safely retry the same purchase after a network failure or app restart.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  findCowryPackageByStoreProductId,
  type StorePaymentProvider,
} from "../_shared/cowry-packages.ts";
import * as appStore from "../_shared/providers/app-store.ts";
import * as googlePlay from "../_shared/providers/google-play.ts";
import { checkAccountDeletion } from "../_shared/account-deletion.ts";
import {
  createStorePurchaseHandler,
  json,
  reject,
  type VerifiedStorePurchase,
} from "./handler.ts";

import { playTransactionRef } from "../_shared/store-refunds.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

async function verify(
  provider: StorePaymentProvider,
  productId: string,
  body: Record<string, unknown>,
): Promise<VerifiedStorePurchase | Response> {
  if (provider === "APP_STORE") {
    if (!appStore.isAppStoreConfigured()) {
      return json({
        error: "App Store purchases are not configured.",
        retryable: true,
      }, 503);
    }
    const transactionId = body.transactionId;
    if (typeof transactionId !== "string" || !/^\d+$/.test(transactionId)) {
      return reject("Invalid request.");
    }
    const tx = await appStore.verifyTransaction(transactionId);
    if (!tx || tx.productId !== productId) {
      return reject("Purchase could not be verified.");
    }
    return {
      txRef: `appstore-${transactionId}`,
      providerRef: transactionId,
      accountId: tx.accountToken,
      amount: tx.amount,
      currency: tx.currency,
      status: tx.status,
      raw: tx.raw,
      quantity: tx.quantity,
      testPurchase: tx.environment !== "Production",
    };
  }

  if (!googlePlay.isGooglePlayConfigured()) {
    return json({
      error: "Google Play purchases are not configured.",
      retryable: true,
    }, 503);
  }
  const purchaseToken = body.purchaseToken;
  if (typeof purchaseToken !== "string" || purchaseToken.length === 0) {
    return reject("Invalid request.");
  }
  const purchase = await googlePlay.verifyPurchase(productId, purchaseToken);
  if (!purchase) return reject("Purchase could not be verified.");
  // Google's purchase record has no price, so amount/currency come from the
  // app's product listing. They're informational only: the cowries credited
  // always come from the product id.
  const amount =
    typeof body.amount === "number" && Number.isFinite(body.amount) &&
      body.amount >= 0
      ? body.amount
      : 0;
  const currency =
    typeof body.currency === "string" && /^[A-Z]{3}$/.test(body.currency)
      ? body.currency
      : "";
  return {
    txRef: await playTransactionRef(purchaseToken),
    providerRef: purchase.orderId ?? purchaseToken,
    accountId: purchase.accountId,
    amount,
    currency,
    status: purchase.status,
    raw: purchase.raw,
    quantity: purchase.quantity,
    testPurchase: purchase.testPurchase,
  };
}

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
const testUserAllowed = (userId: string) =>
  (Deno.env.get("COWRY_STORE_TEST_USER_IDS") ?? "")
    .split(",").map((id) => id.trim().toLowerCase()).filter(Boolean).includes(
      userId.toLowerCase(),
    );

Deno.serve(createStorePurchaseHandler({
  authenticate: async (req) => {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return null;
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data, error } = await userClient.auth.getUser();
    return error ? null : data.user;
  },
  deletionState: (userId) =>
    checkAccountDeletion(() =>
      db.from("account_deletion_requests")
        .select("userId").eq("userId", userId).maybeSingle()
    ),
  configured: (provider) =>
    provider === "APP_STORE"
      ? appStore.isAppStoreConfigured()
      : googlePlay.isGooglePlayConfigured(),
  testUserAllowed,
  checkoutAllowed: (userId, provider) => {
    const mode = Deno.env.get(
      provider === "GOOGLE_PLAY"
        ? "COWRY_STORE_CHECKOUT_MODE"
        : "APP_STORE_CHECKOUT_MODE",
    );
    return mode === "live" || (mode === "testing" && testUserAllowed(userId));
  },
  verify,
  fulfill: async (verified, userId, provider, productId) => {
    const packageDefinition = findCowryPackageByStoreProductId(productId)!;
    const { error: insertError } = await db.from("cowry_payments").insert({
      txRef: verified.txRef,
      provider,
      providerRef: verified.providerRef,
      status: "PENDING",
      currency: verified.currency,
      amount: verified.amount,
      cowries: packageDefinition.cowries,
      packageId: packageDefinition.id,
      userId,
      rawResponse: verified.raw,
      updatedAt: new Date().toISOString(),
    });
    if (insertError) {
      if (insertError.code !== "23505") {
        console.error(
          `[cowry-store] ${verified.txRef}: insert failed`,
          insertError.code,
        );
        return json(
          { error: "Unable to record purchase.", retryable: true },
          500,
        );
      }
      // Already recorded by an earlier attempt: credit_cowry_payment below
      // either finishes it or reports it as already processed.
      const { data: existing, error: lookupError } = await db
        .from("cowry_payments")
        .select("userId")
        .eq("txRef", verified.txRef)
        .maybeSingle();
      if (lookupError || !existing) {
        return json(
          { error: "Unable to reconcile purchase.", retryable: true },
          503,
        );
      }
      if (existing.userId !== userId) {
        return reject("This purchase belongs to a different account.", 409);
      }
    }

    const { data: creditResult, error } = await db.rpc("credit_cowry_payment", {
      p_tx_ref: verified.txRef,
      p_status: "SUCCESSFUL",
      p_provider_ref: verified.providerRef,
      p_raw_response: verified.raw,
    });
    if (error) {
      console.error(
        `[cowry-store] ${verified.txRef}: credit_cowry_payment failed`,
        error.code,
      );
      return json({ error: "Failed to credit cowries.", retryable: true }, 500);
    }
    const result = creditResult as {
      success: boolean;
      error?: string;
      cowryBalance?: number;
      alreadyProcessed?: boolean;
    };
    if (!result?.success) {
      return reject(result?.error ?? "Failed to credit cowries.", 409);
    }
    return json({
      success: true,
      cowryBalance: result.cowryBalance,
      alreadyProcessed: result.alreadyProcessed ?? false,
    });
  },
}));
