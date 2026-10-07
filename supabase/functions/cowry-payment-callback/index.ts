// Mirrors neolingo: src/app/api/payments/{flutterwave,paystack}/callback/route.ts
// and .../webhook/route.ts, plus the shared src/lib/payments/verification.ts
// (verifyAndFulfillPayment) + fulfillment.ts. Deployed with JWT verification
// OFF — the payment provider's redirect/webhook has no Supabase session.
import { createClient } from "jsr:@supabase/supabase-js@2";
import type { CowryPaymentProvider } from "../_shared/cowry-packages.ts";
import * as flutterwave from "../_shared/providers/flutterwave.ts";
import * as paystack from "../_shared/providers/paystack.ts";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function completeUrl(payment: "success" | "failed" | "missing", returnTo: string) {
  return (
    `${SUPABASE_URL}/functions/v1/cowry-payment-callback/complete` +
    `?payment=${payment}&return_to=${encodeURIComponent(returnTo)}`
  );
}

async function resolveTxRefByProviderRef(
  provider: CowryPaymentProvider,
  providerRef: string,
): Promise<string | null> {
  const { data } = await db
    .from("cowry_payments")
    .select("txRef")
    .eq("provider", provider)
    .eq("providerRef", providerRef)
    .limit(2);
  return data && data.length === 1 ? (data[0].txRef as string) : null;
}

interface FulfillResult {
  success: boolean;
  error?: string;
  alreadyProcessed?: boolean;
}

// Re-verifies with the provider server-side (never trusts the redirect
// query params' own status) before crediting — same contract as
// verifyAndFulfillPayment.
async function verifyAndFulfill(
  provider: CowryPaymentProvider,
  txRef: string,
  providerRef?: string,
): Promise<FulfillResult> {
  const { data: payment } = await db
    .from("cowry_payments")
    .select("*")
    .eq("txRef", txRef)
    .maybeSingle();
  if (!payment) return { success: false, error: "Payment record was not found." };
  if (payment.provider !== provider) return { success: false, error: "Payment provider mismatch." };

  const adapter = provider === "FLUTTERWAVE" ? flutterwave : paystack;
  const verified = await adapter.verify({
    txRef,
    providerRef: providerRef ?? payment.providerRef ?? undefined,
  });
  if (!verified || verified.provider !== provider || verified.txRef !== txRef) {
    return { success: false, error: "Payment verification failed." };
  }

  // matchesPayment: force FAILED_VERIFICATION if the provider's reported
  // amount/currency disagree with what was stored at initiate time, even
  // when the provider reports success.
  const matches = Number(payment.amount) === verified.amount && payment.currency === verified.currency;
  const status = verified.status === "SUCCESSFUL" && !matches ? "FAILED_VERIFICATION" : verified.status;

  const { data: creditResult, error } = await db.rpc("credit_cowry_payment", {
    p_tx_ref: txRef,
    p_status: status,
    p_provider_ref: verified.providerRef,
    p_raw_response: verified.rawResponse,
  });
  if (error) return { success: false, error: "Failed to credit cowries." };
  return creditResult as FulfillResult;
}

async function handleUserCallback(provider: "flutterwave" | "paystack", url: URL): Promise<Response> {
  const returnTo = url.searchParams.get("return_to") ?? "awaquiz";
  const cowryProvider: CowryPaymentProvider = provider === "flutterwave" ? "FLUTTERWAVE" : "PAYSTACK";

  let txRef: string | null;
  let providerRef: string | undefined;
  if (provider === "flutterwave") {
    txRef = url.searchParams.get("tx_ref") ?? url.searchParams.get("reference");
    providerRef =
      url.searchParams.get("transaction_id") ??
      url.searchParams.get("id") ??
      url.searchParams.get("charge_id") ??
      undefined;
    if (!txRef && providerRef) {
      txRef = await resolveTxRefByProviderRef("FLUTTERWAVE", providerRef);
    }
  } else {
    txRef = url.searchParams.get("reference");
  }

  if (!txRef) {
    return Response.redirect(completeUrl("missing", returnTo), 302);
  }

  const result = await verifyAndFulfill(cowryProvider, txRef, providerRef);
  return Response.redirect(completeUrl(result.success ? "success" : "failed", returnTo), 302);
}

async function handleWebhook(provider: "flutterwave" | "paystack", req: Request): Promise<Response> {
  const rawBody = await req.text();
  if (provider === "flutterwave") {
    const ok = await flutterwave.verifyWebhookSignature(rawBody, req.headers.get("flutterwave-signature"));
    if (!ok) return json({ error: "Invalid signature" }, 401);
    const body = JSON.parse(rawBody);
    const providerRef = body?.data?.id != null ? String(body.data.id) : undefined;
    const reference = body?.data?.reference as string | undefined;
    const txRef = reference ?? (providerRef ? await resolveTxRefByProviderRef("FLUTTERWAVE", providerRef) : null);
    if (!txRef) return json({ ok: true });
    await verifyAndFulfill("FLUTTERWAVE", txRef, providerRef);
    return json({ ok: true });
  }

  const ok = await paystack.verifyWebhookSignature(rawBody, req.headers.get("x-paystack-signature"));
  if (!ok) return json({ error: "Invalid signature" }, 401);
  const body = JSON.parse(rawBody);
  if (body.event !== "charge.success") return json({ ok: true });
  const txRef = body?.data?.reference as string | undefined;
  if (!txRef) return json({ ok: true });
  await verifyAndFulfill("PAYSTACK", txRef);
  return json({ ok: true });
}

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const idx = parts.indexOf("cowry-payment-callback");
  const sub = idx >= 0 ? parts.slice(idx + 1) : parts;

  if (sub[0] === "complete") {
    // Fixed marker URL Flutter's WebView intercepts and never actually lets
    // load — this response only matters if something else visits it directly.
    return json({ ok: true });
  }

  if (req.method === "GET" && (sub[0] === "flutterwave" || sub[0] === "paystack")) {
    return handleUserCallback(sub[0], url);
  }

  if (req.method === "POST" && sub[0] === "webhook" && (sub[1] === "flutterwave" || sub[1] === "paystack")) {
    return handleWebhook(sub[1], req);
  }

  return json({ error: "Not found" }, 404);
});
