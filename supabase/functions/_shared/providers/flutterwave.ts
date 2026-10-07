// Mirrors neolingo: src/lib/payments/flutterwave.ts — same API calls, same
// env var names, so existing Flutterwave dashboard config (webhook hash,
// client id/secret) can be reused verbatim for this function's secrets.

const FLUTTERWAVE_API_URL =
  Deno.env.get("FLUTTERWAVE_API_URL") ??
  "https://developersandbox-api.flutterwave.com";
const FLUTTERWAVE_AUTH_URL =
  Deno.env.get("FLUTTERWAVE_AUTH_URL") ??
  "https://idp.flutterwave.com/realms/flutterwave/protocol/openid-connect/token";
const FLUTTERWAVE_PAYMENT_METHOD_TYPE =
  Deno.env.get("FLUTTERWAVE_PAYMENT_METHOD_TYPE") ?? "opay";

export type PaymentStatus = "SUCCESSFUL" | "FAILED" | "PENDING";

export interface InitiateInput {
  amount: number;
  currency: string;
  customerEmail: string;
  customerName: string;
  packageId: string;
  cowries: number;
  returnUrl: string;
  txRef: string;
}

export interface InitiateResult {
  success: boolean;
  checkoutUrl?: string;
  providerRef?: string;
  rawResponse?: unknown;
  error?: string;
}

export interface VerifyInput {
  txRef: string;
  providerRef?: string;
}

export interface VerifiedPayment {
  amount: number;
  currency: string;
  provider: "FLUTTERWAVE";
  providerRef: string;
  rawResponse: unknown;
  status: PaymentStatus;
  txRef: string;
}

export function isFlutterwaveConfigured(): boolean {
  return Boolean(Deno.env.get("FLW_CLIENT_ID") && Deno.env.get("FLW_CLIENT_SECRET"));
}

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now()) {
    return cachedToken.token;
  }
  const clientId = Deno.env.get("FLW_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("FLW_CLIENT_SECRET") ?? "";
  const response = await fetch(FLUTTERWAVE_AUTH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!response.ok) {
    throw new Error(`Flutterwave auth failed: ${response.status}`);
  }
  const body = await response.json();
  const token = body.access_token as string;
  const expiresIn = Number(body.expires_in ?? 0);
  cachedToken = { token, expiresAt: Date.now() + (expiresIn - 60) * 1000 };
  return token;
}

function getCheckoutUrl(data: Record<string, unknown>): string | undefined {
  const inner = (data.data ?? {}) as Record<string, unknown>;
  const nextAction = inner.next_action as Record<string, unknown> | undefined;
  const redirect = nextAction?.redirect_url as Record<string, unknown> | undefined;
  return (
    (redirect?.url as string | undefined) ??
    (inner.redirect_url as string | undefined) ??
    (inner.link as string | undefined) ??
    (data.link as string | undefined)
  );
}

export async function initiate(input: InitiateInput): Promise<InitiateResult> {
  try {
    const token = await getAccessToken();
    const [firstName, ...rest] = input.customerName.trim().split(/\s+/);
    const response = await fetch(`${FLUTTERWAVE_API_URL}/orchestration/direct-charges`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
        "X-Trace-Id": input.txRef,
        "X-Idempotency-Key": input.txRef,
      },
      body: JSON.stringify({
        reference: input.txRef,
        amount: input.amount,
        currency: input.currency,
        redirect_url: input.returnUrl,
        customer: {
          email: input.customerEmail,
          name: { first: firstName || "Awalingo", last: rest.join(" ") || "User" },
        },
        payment_method: { type: FLUTTERWAVE_PAYMENT_METHOD_TYPE },
        meta: { cowries: input.cowries, packageId: input.packageId },
      }),
    });
    const body = await response.json();
    const checkoutUrl = getCheckoutUrl(body);
    if (body.status !== "success" || !checkoutUrl) {
      return { success: false, error: body.message ?? "Flutterwave initiation failed.", rawResponse: body };
    }
    const chargeId = (body.data ?? {}).id;
    return {
      success: true,
      checkoutUrl,
      providerRef: chargeId != null ? String(chargeId) : undefined,
      rawResponse: body,
    };
  } catch (error) {
    return { success: false, error: error instanceof Error ? error.message : "Flutterwave initiation failed." };
  }
}

function normalizeStatus(status: string | undefined): PaymentStatus {
  const normalized = (status ?? "").toLowerCase();
  if (normalized === "successful" || normalized === "succeeded") return "SUCCESSFUL";
  if (normalized === "failed" || normalized === "cancelled" || normalized === "canceled") return "FAILED";
  return "PENDING";
}

// HMAC-SHA256 base64 digest against the `flutterwave-signature` header —
// mirrors verifyFlutterwaveWebhookSignature (neolingo:
// src/lib/payments/flutterwave-webhook.ts).
export async function verifyWebhookSignature(
  rawBody: string,
  signature: string | null,
): Promise<boolean> {
  const secret = Deno.env.get("FLUTTERWAVE_WEBHOOK_HASH");
  if (!secret || !signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const computed = btoa(String.fromCharCode(...new Uint8Array(digest)));
  if (computed.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < computed.length; i++) {
    mismatch |= computed.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return mismatch === 0;
}

export async function verify(input: VerifyInput): Promise<VerifiedPayment | null> {
  if (!input.providerRef) return null;
  const token = await getAccessToken();
  const response = await fetch(`${FLUTTERWAVE_API_URL}/charges/${input.providerRef}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const body = await response.json();
  if (body.status !== "success" || !body.data) return null;
  const transaction = body.data;
  if (transaction.reference !== input.txRef) return null;
  return {
    amount: Number(transaction.amount),
    currency: String(transaction.currency),
    provider: "FLUTTERWAVE",
    providerRef: String(transaction.id),
    rawResponse: transaction,
    status: normalizeStatus(transaction.status),
    txRef: input.txRef,
  };
}
