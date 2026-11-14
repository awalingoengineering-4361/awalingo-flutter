// Verifies an App Store in-app purchase by looking the transaction up with
// the App Store Server API, so the credit never depends on data the app
// itself sends. Needs an In-App Purchase key from App Store Connect
// (Users and Access → Integrations → In-App Purchase).
import { decodeJwsPayload, signJwt } from "./store-auth.ts";

const PRODUCTION_URL = "https://api.storekit.itunes.apple.com";
const SANDBOX_URL = "https://api.storekit-sandbox.itunes.apple.com";

export interface StoreTransaction {
  transactionId: string;
  productId: string;
  accountToken?: string;
  amount: number;
  currency: string;
  status: "SUCCESSFUL" | "FAILED" | "PENDING";
  environment: string;
  raw: unknown;
}

export function isAppStoreConfigured(): boolean {
  return Boolean(
    Deno.env.get("APP_STORE_ISSUER_ID") &&
      Deno.env.get("APP_STORE_KEY_ID") &&
      Deno.env.get("APP_STORE_PRIVATE_KEY") &&
      Deno.env.get("APP_STORE_BUNDLE_ID"),
  );
}

async function apiToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return signJwt(
    { kid: Deno.env.get("APP_STORE_KEY_ID") },
    {
      iss: Deno.env.get("APP_STORE_ISSUER_ID"),
      iat: now,
      exp: now + 15 * 60,
      aud: "appstoreconnect-v1",
      bid: Deno.env.get("APP_STORE_BUNDLE_ID"),
    },
    Deno.env.get("APP_STORE_PRIVATE_KEY") ?? "",
    "ES256",
  );
}

// Tries production first, then sandbox: TestFlight and Xcode test purchases
// only exist in sandbox, and Apple answers 404 for the other environment.
export async function verifyTransaction(transactionId: string): Promise<StoreTransaction | null> {
  const token = await apiToken();
  for (const baseUrl of [PRODUCTION_URL, SANDBOX_URL]) {
    const response = await fetch(
      `${baseUrl}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (response.status === 404) continue;
    if (!response.ok) {
      throw new Error(`App Store lookup failed: ${response.status} ${await response.text()}`);
    }
    const body = await response.json();
    const info = decodeJwsPayload(body.signedTransactionInfo as string);
    if (info.bundleId !== Deno.env.get("APP_STORE_BUNDLE_ID")) return null;
    if (String(info.transactionId) !== transactionId) return null;
    return {
      transactionId,
      productId: String(info.productId),
      accountToken: info.appAccountToken ? String(info.appAccountToken).toLowerCase() : undefined,
      // price is in milliunits of the storefront currency.
      amount: typeof info.price === "number" ? info.price / 1000 : 0,
      currency: typeof info.currency === "string" ? info.currency : "",
      status: info.revocationDate ? "FAILED" : "SUCCESSFUL",
      environment: String(info.environment ?? ""),
      raw: info,
    };
  }
  return null;
}
