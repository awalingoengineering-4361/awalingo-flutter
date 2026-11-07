// Credits cowries for an App Store or Google Play in-app purchase made in
// the iOS/Android app. Deployed with JWT verification ON — the app sends the
// signed-in user's Supabase access token, like cowry-payment-initiate.
//
// The app only says which transaction it saw; the transaction itself is
// looked up with Apple/Google before anything is credited. Each store
// transaction maps to one cowry_payments row (txRef is unique), and
// credit_cowry_payment only credits a PENDING row once, so the app can
// safely retry the same purchase after a network failure or app restart.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { findCowryPackageByStoreProductId, type StorePaymentProvider } from "../_shared/cowry-packages.ts";
import * as appStore from "../_shared/providers/app-store.ts";
import * as googlePlay from "../_shared/providers/google-play.ts";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// retryable: false tells the app the purchase will never be credited, so it
// can finish the transaction with the store instead of retrying forever.
function reject(error: string, status = 400) {
  return json({ success: false, retryable: false, error }, status);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface VerifiedStorePurchase {
  txRef: string;
  providerRef: string;
  accountId?: string;
  amount: number;
  currency: string;
  status: "SUCCESSFUL" | "FAILED" | "PENDING";
  raw: unknown;
}

async function verify(
  provider: StorePaymentProvider,
  productId: string,
  body: Record<string, unknown>,
): Promise<VerifiedStorePurchase | Response> {
  if (provider === "APP_STORE") {
    if (!appStore.isAppStoreConfigured()) return json({ error: "App Store purchases are not configured.", retryable: true }, 503);
    const transactionId = body.transactionId;
    if (typeof transactionId !== "string" || !/^\d+$/.test(transactionId)) return reject("Invalid request.");
    const tx = await appStore.verifyTransaction(transactionId);
    if (!tx || tx.productId !== productId) return reject("Purchase could not be verified.");
    return {
      txRef: `appstore-${transactionId}`,
      providerRef: transactionId,
      accountId: tx.accountToken,
      amount: tx.amount,
      currency: tx.currency,
      status: tx.status,
      raw: tx.raw,
    };
  }

  if (!googlePlay.isGooglePlayConfigured()) return json({ error: "Google Play purchases are not configured.", retryable: true }, 503);
  const purchaseToken = body.purchaseToken;
  if (typeof purchaseToken !== "string" || purchaseToken.length === 0) return reject("Invalid request.");
  const purchase = await googlePlay.verifyPurchase(productId, purchaseToken);
  if (!purchase) return reject("Purchase could not be verified.");
  // Google's purchase record has no price, so amount/currency come from the
  // app's product listing. They're informational only: the cowries credited
  // always come from the product id.
  const amount = typeof body.amount === "number" && Number.isFinite(body.amount) && body.amount >= 0 ? body.amount : 0;
  const currency = typeof body.currency === "string" && /^[A-Z]{3}$/.test(body.currency) ? body.currency : "";
  return {
    txRef: `play-${(await sha256Hex(purchaseToken)).slice(0, 40)}`,
    providerRef: purchase.orderId ?? purchaseToken,
    accountId: purchase.accountId,
    amount,
    currency,
    status: purchase.status,
    raw: purchase.raw,
  };
}

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401);
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);
  const user = userData.user;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reject("Invalid request body.");
  }

  const provider = body.provider;
  const productId = body.productId;
  if ((provider !== "APP_STORE" && provider !== "GOOGLE_PLAY") || typeof productId !== "string") {
    return reject("Invalid request.");
  }
  const packageDefinition = findCowryPackageByStoreProductId(productId);
  if (!packageDefinition) return reject("Unknown product.");

  let verified: VerifiedStorePurchase | Response;
  try {
    verified = await verify(provider, productId, body);
  } catch (error) {
    console.error(`[cowry-store] ${provider} ${productId}: store lookup failed`, error);
    return json({ error: "Could not reach the store. Please try again.", retryable: true }, 502);
  }
  if (verified instanceof Response) return verified;

  // The app tags every purchase with the buyer's user id (appAccountToken /
  // obfuscatedAccountId), so one account can't claim another's receipt.
  if (verified.accountId && verified.accountId !== user.id.toLowerCase()) {
    return reject("This purchase belongs to a different account.", 403);
  }
  if (verified.status === "PENDING") {
    return json({ success: false, pending: true }, 202);
  }
  if (verified.status === "FAILED") {
    return reject("This purchase was cancelled or refunded.");
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { error: insertError } = await db.from("cowry_payments").insert({
    txRef: verified.txRef,
    provider,
    providerRef: verified.providerRef,
    status: "PENDING",
    currency: verified.currency,
    amount: verified.amount,
    cowries: packageDefinition.cowries,
    packageId: packageDefinition.id,
    userId: user.id,
    rawResponse: verified.raw,
    updatedAt: new Date().toISOString(),
  });
  if (insertError) {
    if (insertError.code !== "23505") {
      console.error(`[cowry-store] ${verified.txRef}: insert failed`, insertError);
      return json({ error: "Unable to record purchase.", retryable: true }, 500);
    }
    // Already recorded by an earlier attempt: credit_cowry_payment below
    // either finishes it or reports it as already processed.
    const { data: existing } = await db
      .from("cowry_payments")
      .select("userId")
      .eq("txRef", verified.txRef)
      .maybeSingle();
    if (existing && existing.userId !== user.id) {
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
    console.error(`[cowry-store] ${verified.txRef}: credit_cowry_payment failed`, error);
    return json({ error: "Failed to credit cowries.", retryable: true }, 500);
  }
  const result = creditResult as { success: boolean; error?: string; cowryBalance?: number; alreadyProcessed?: boolean };
  if (!result.success) return reject(result.error ?? "Failed to credit cowries.", 409);
  return json({ success: true, cowryBalance: result.cowryBalance, alreadyProcessed: result.alreadyProcessed ?? false });
});
