// Verifies a Google Play in-app purchase with the Play Developer API, so the
// credit never depends on data the app itself sends. Needs a Google Cloud
// service account with access to the app in the Play Console (Users and
// permissions → "View financial data").
import { signJwt } from "./store-auth.ts";

export interface PlayPurchase {
  orderId?: string;
  accountId?: string;
  status: "SUCCESSFUL" | "FAILED" | "PENDING";
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
    { headers: { Authorization: `Bearer ${await accessToken()}` } },
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
    raw: body,
  };
}
