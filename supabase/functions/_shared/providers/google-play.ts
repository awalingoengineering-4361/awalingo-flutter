// Verifies a Google Play in-app purchase with the Play Developer API, so the
// credit never depends on data the app itself sends. Needs a Google Cloud
// service account with access to the app in the Play Console (Users and
// permissions → "View financial data").
import { signJwt } from "./store-auth.ts";

export interface PlayPurchase {
  orderId?: string;
  accountId?: string;
  status: "SUCCESSFUL" | "FAILED" | "PENDING";
  quantity: number;
  testPurchase: boolean;
  raw: unknown;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

export function isGooglePlayConfigured(): boolean {
  return Boolean(
    Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") && Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"),
  );
}

let cachedToken: { token: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.token;
  const account = JSON.parse(Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "{}") as ServiceAccount;
  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt(
    {},
    {
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    },
    account.private_key,
    "RS256",
  );
  const response = await fetch(tokenUri, {
    method: "POST",
    signal: AbortSignal.timeout(15_000),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Google auth failed: ${response.status}`);
  const body = await response.json();
  cachedToken = { token: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return cachedToken.token;
}

// Returns null when Google doesn't know the token for this product.
export async function verifyPurchase(productId: string, purchaseToken: string): Promise<PlayPurchase | null> {
  const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ?? "";
  const response = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}` +
      `/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}`,
    { headers: { Authorization: `Bearer ${await accessToken()}` }, signal: AbortSignal.timeout(15_000) },
  );
  if (response.status === 404 || response.status === 400) return null;
  if (!response.ok) {
    throw new Error(`Google Play lookup failed: ${response.status} ${await response.text()}`);
  }
  const body = await response.json();
  // purchaseState: 0 purchased, 1 canceled, 2 pending.
  const status = body.purchaseState === 0 ? "SUCCESSFUL" : body.purchaseState === 2 ? "PENDING" : "FAILED";
  return {
    orderId: body.orderId ?? undefined,
    accountId: body.obfuscatedExternalAccountId ?? undefined,
    status,
    quantity: body.quantity ?? 1,
    testPurchase: body.purchaseType === 0,
    raw: body,
  };
}


/** Only Google's authenticated API supplies refund input, never a public webhook body. */
export async function listVoidedPurchases(page?: string): Promise<{
  purchases: { purchaseToken: string }[]; nextPage?: string;
}> {
  const packageName = Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME") ?? "";
  const url = new URL(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/voidedpurchases`);
  url.searchParams.set("maxResults", "1000");
  url.searchParams.set("type", "0");
  url.searchParams.set("includeQuantityBasedPartialRefund", "true");
  // Omitting startTime uses Google's complete 30-day window; each hourly
  // run overlaps, so missed jobs and duplicate pages cannot lose a refund.
  if (page) url.searchParams.set("token", page);
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${await accessToken()}` },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`Google voided purchases lookup failed: ${response.status}`);
  const body = await response.json();
  if (body.voidedPurchases !== undefined && !Array.isArray(body.voidedPurchases)) throw new Error("Invalid voided purchases response");
  return { purchases: body.voidedPurchases ?? [], nextPage: body.tokenPagination?.nextPageToken ?? undefined };
}
