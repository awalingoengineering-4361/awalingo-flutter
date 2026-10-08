// Mirrors neolingo: src/lib/payments/paystack.ts — same API calls, same env
// var names, so the existing Paystack dashboard secret key can be reused
// verbatim for this function's secrets.
import type { InitiateInput, InitiateResult, PaymentStatus, VerifiedPayment, VerifyInput } from "./flutterwave.ts";

const PAYSTACK_API_URL = Deno.env.get("PAYSTACK_API_URL") ?? "https://api.paystack.co";

export function isPaystackConfigured(): boolean {
  return Boolean(Deno.env.get("PAYSTACK_SECRET_KEY"));
}

function secretKey(): string {
  return Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";
}

export async function initiate(input: InitiateInput): Promise<InitiateResult> {
  try {
    const response = await fetch(`${PAYSTACK_API_URL}/transaction/initialize`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${secretKey()}`,
      },
      body: JSON.stringify({
        amount: String(Math.round(input.amount * 100)), // kobo/cents, integer
        callback_url: input.returnUrl,
        currency: input.currency,
        email: input.customerEmail,
        metadata: JSON.stringify({ packageId: input.packageId }),
        reference: input.txRef,
      }),
    });
    const body = await response.json();
    if (!body.status || !body.data?.authorization_url || !body.data?.reference) {
      return { success: false, error: body.message ?? "Paystack initiation failed.", rawResponse: body };
    }
    return {
      success: true,
      checkoutUrl: body.data.authorization_url,
      providerRef: body.data.reference,
      rawResponse: body,
    };
  } catch (error) {
    return { success: false, error: error instanceof Error ? error.message : "Paystack initiation failed." };
  }
}

function normalizeStatus(status: string | undefined): PaymentStatus {
  const normalized = (status ?? "").toLowerCase();
  if (normalized === "success") return "SUCCESSFUL";
  if (normalized === "abandoned" || normalized === "failed" || normalized === "reversed") return "FAILED";
  return "PENDING";
}

export async function verify(input: VerifyInput): Promise<VerifiedPayment | null> {
  const response = await fetch(
    `${PAYSTACK_API_URL}/transaction/verify/${encodeURIComponent(input.txRef)}`,
    { headers: { Authorization: `Bearer ${secretKey()}` } },
  );
  const body = await response.json();
  const data = body.data;
  if (!body.status || !data?.id || !data?.reference || !data?.status || !data?.currency) {
    return null;
  }
  const amount = Number(data.amount);
  if (!Number.isFinite(amount) || amount < 0) return null;
  if (data.reference !== input.txRef) return null;
  return {
    amount: amount / 100, // kobo/cents -> major unit
    currency: String(data.currency),
    provider: "PAYSTACK",
    providerRef: String(data.id),
    rawResponse: body,
    status: normalizeStatus(data.status),
    txRef: input.txRef,
  };
}

// HMAC-SHA512 hex digest, timing-safe compare — mirrors
// verifyPaystackWebhookSignature (neolingo: src/lib/payments/paystack.ts).
export async function verifyWebhookSignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature || !/^[a-f\d]{128}$/i.test(signature)) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secretKey()),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const computed = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return timingSafeEqual(computed, signature.toLowerCase());
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
