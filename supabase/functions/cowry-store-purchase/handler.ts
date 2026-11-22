import {
  findCowryPackageByStoreProductId,
  type StorePaymentProvider,
} from "../_shared/cowry-packages.ts";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";

export interface VerifiedStorePurchase {
  txRef: string;
  providerRef: string;
  accountId?: string;
  amount: number;
  currency: string;
  status: "SUCCESSFUL" | "FAILED" | "PENDING";
  quantity: number;
  testPurchase: boolean;
  raw: unknown;
}

export interface StorePurchaseDependencies {
  authenticate(req: Request): Promise<{ id: string } | null>;
  deletionState(userId: string): Promise<"active" | "deleting" | "unavailable">;
  configured(provider: StorePaymentProvider): boolean;
  testUserAllowed(userId: string): boolean;
  checkoutAllowed(userId: string, provider: StorePaymentProvider): boolean;
  verify(
    provider: StorePaymentProvider,
    productId: string,
    body: Record<string, unknown>,
  ): Promise<VerifiedStorePurchase | Response>;
  fulfill(
    purchase: VerifiedStorePurchase,
    userId: string,
    provider: StorePaymentProvider,
    productId: string,
  ): Promise<Response>;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// Rejection never authorizes client consumption. The owner can retry after
// correcting configuration/sign-in; revoked purchases are handled by the store.
export function reject(error: string, status = 400): Response {
  return json({ success: false, retryable: false, error }, status);
}

export function createStorePurchaseHandler(deps: StorePurchaseDependencies) {
  return async (req: Request): Promise<Response> => {
    const preflight = handleCorsPreflight(req);
    if (preflight) return preflight;
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    let user: { id: string } | null;
    try {
      user = await deps.authenticate(req);
    } catch {
      return json(
        { error: "Authentication unavailable", retryable: true },
        503,
      );
    }
    if (!user) return json({ error: "Unauthorized" }, 401);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        return reject("Invalid request body.");
      }
    } catch {
      return reject("Invalid request body.");
    }
    const { provider, productId, action } = body;
    if (
      (provider !== "APP_STORE" && provider !== "GOOGLE_PLAY") ||
      typeof productId !== "string" ||
      !findCowryPackageByStoreProductId(productId) ||
      (action !== undefined && action !== "eligibility")
    ) return reject("Invalid request.");
    let state: "active" | "deleting" | "unavailable";
    try {
      state = await deps.deletionState(user.id);
    } catch {
      state = "unavailable";
    }
    if (state === "deleting") {
      return reject(
        "This account is being deleted and cannot buy cowries.",
        403,
      );
    }
    if (state !== "active") {
      return json({
        error: "Unable to check account eligibility.",
        retryable: true,
      }, 503);
    }
    if (!deps.configured(provider)) {
      return json({
        error: "Store purchases are not configured.",
        retryable: true,
      }, 503);
    }
    if (action === "eligibility") {
      if (!deps.checkoutAllowed(user.id, provider)) {
        return reject("Store checkout is not enabled for this account.", 403);
      }
      return json({ eligible: true });
    }
    let purchase: VerifiedStorePurchase | Response;
    try {
      purchase = await deps.verify(provider, productId, body);
    } catch {
      return json({
        error: "Could not reach the store. Please try again.",
        retryable: true,
      }, 502);
    }
    if (purchase instanceof Response) return purchase;
    if (purchase.status === "PENDING") {
      return json({ success: false, pending: true }, 202);
    }
    if (purchase.status !== "SUCCESSFUL") {
      return reject("This purchase was cancelled or refunded.");
    }
    if (
      !purchase.accountId ||
      purchase.accountId.toLowerCase() !== user.id.toLowerCase()
    ) {
      return reject(
        "This purchase is not bound to the signed-in account.",
        403,
      );
    }
    if (purchase.quantity !== 1) {
      return reject(
        "This purchase quantity requires support. It has not been consumed.",
        409,
      );
    }
    if (purchase.testPurchase && !deps.testUserAllowed(user.id)) {
      return reject("Test purchases are not enabled for this account.", 403);
    }
    try {
      const latestState = await deps.deletionState(user.id);
      if (latestState === "deleting") {
        return reject(
          "This account is being deleted and cannot buy cowries.",
          403,
        );
      }
      if (latestState !== "active") {
        return json({
          error: "Unable to check account eligibility.",
          retryable: true,
        }, 503);
      }
      return await deps.fulfill(purchase, user.id, provider, productId);
    } catch {
      return json({
        error: "Unable to fulfill purchase. Please try again.",
        retryable: true,
      }, 503);
    }
  };
}
