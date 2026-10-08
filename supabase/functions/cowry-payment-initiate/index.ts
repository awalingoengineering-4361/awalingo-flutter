// Mirrors neolingo: src/lib/payments/initiation.ts (initiateCowryPayment).
// Deployed with JWT verification ON — only an authenticated app user's
// Supabase access token (the same Bearer token payment_service.dart already
// sends) can call this.
//
// Deviation from the source: currency there is resolved server-side from
// Vercel/Cloudflare's injected IP-geolocation headers, which don't exist on
// Supabase's Edge Function runtime. The Flutter client already resolves its
// own currency via ipapi.co for pricing display (loadPaymentOptions), so it
// is passed through explicitly here instead of being re-derived blind.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  findCowryPackageDefinition,
  PROVIDER_DEFINITIONS,
  type CowryPaymentProvider,
} from "../_shared/cowry-packages.ts";
import { createCowryPaymentReference } from "../_shared/reference.ts";
import * as flutterwave from "../_shared/providers/flutterwave.ts";
import * as paystack from "../_shared/providers/paystack.ts";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const INITIALIZATION_TIMEOUT_MS = 2 * 60 * 1000;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// cowry_payments.updatedAt has no DB-level default (Prisma's @updatedAt is
// applied client-side by Prisma itself, not by the column) — every insert
// and update from here must set it explicitly or the NOT NULL constraint
// rejects the write.
function nowIso(): string {
  return new Date().toISOString();
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
    return json({ error: "Invalid request body." }, 400);
  }

  const attemptKey = body.attemptKey;
  const packageId = body.packageId;
  const provider = body.provider;
  const currency = body.currency;
  const returnTo = typeof body.returnTo === "string" ? body.returnTo : "awaquiz";

  if (
    typeof attemptKey !== "string" ||
    typeof packageId !== "string" ||
    (provider !== "FLUTTERWAVE" && provider !== "PAYSTACK") ||
    (currency !== "NGN" && currency !== "USD")
  ) {
    return json({ error: "Invalid request." }, 400);
  }

  const packageDefinition = findCowryPackageDefinition(packageId);
  if (!packageDefinition) return json({ error: "Unknown package." }, 400);

  const providerMeta = PROVIDER_DEFINITIONS[provider as CowryPaymentProvider];
  if (!providerMeta.supportedCurrencies.includes(currency)) {
    return json({ error: `${provider} does not support ${currency}.` }, 400);
  }

  if (provider === "FLUTTERWAVE" && !flutterwave.isFlutterwaveConfigured()) {
    return json({ error: "Flutterwave is not configured.", retryable: false }, 503);
  }
  if (provider === "PAYSTACK" && !paystack.isPaystackConfigured()) {
    return json({ error: "Paystack is not configured.", retryable: false }, 503);
  }

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: priceRow } = await db
    .from("cowry_package_prices")
    .select("amount, enabled")
    .eq("packageId", packageId)
    .eq("currency", currency)
    .maybeSingle();
  if (!priceRow || !priceRow.enabled) {
    return json({ error: "Top-ups are currently unavailable.", retryable: false }, 503);
  }
  const amount = Number(priceRow.amount);
  const minimum = providerMeta.minimumAmounts[currency];
  if (minimum != null && amount < minimum) {
    return json({ error: "Package amount is below the provider minimum.", retryable: false }, 400);
  }

  const { data: existingAttempt } = await db
    .from("cowry_payments")
    .select("*")
    .eq("userId", user.id)
    .eq("attemptKey", attemptKey)
    .maybeSingle();

  if (existingAttempt) {
    const matches =
      existingAttempt.provider === provider &&
      existingAttempt.packageId === packageId &&
      existingAttempt.currency === currency &&
      Number(existingAttempt.amount) === amount;
    if (!matches) {
      return json(
        { error: "This attempt does not match a previous selection.", retryable: false },
        409,
      );
    }
    if (existingAttempt.status === "PENDING" && existingAttempt.checkoutUrl) {
      return json({ checkoutUrl: existingAttempt.checkoutUrl });
    }
    if (existingAttempt.status === "INITIALIZING") {
      const age = Date.now() - new Date(existingAttempt.updatedAt).getTime();
      if (age < INITIALIZATION_TIMEOUT_MS) {
        return json({ error: "Payment initialization already in progress.", retryable: true }, 409);
      }
      await db
        .from("cowry_payments")
        .update({ status: "INIT_FAILED", updatedAt: nowIso() })
        .eq("id", existingAttempt.id);
    } else if (existingAttempt.status !== "INIT_FAILED") {
      return json({ error: "This payment attempt has already been completed.", retryable: false }, 409);
    }
  }

  const txRef = createCowryPaymentReference(user.id);
  const cowries = packageDefinition.cowries;

  let paymentRow: { id: number };
  if (existingAttempt && existingAttempt.status === "INIT_FAILED") {
    const { data, error } = await db
      .from("cowry_payments")
      .update({
        status: "INITIALIZING",
        txRef,
        provider,
        currency,
        amount,
        cowries,
        packageId,
        updatedAt: nowIso(),
      })
      .eq("id", existingAttempt.id)
      .select("id")
      .single();
    if (error || !data) return json({ error: "Unable to start payment.", retryable: true }, 500);
    paymentRow = data;
  } else {
    const { data, error } = await db
      .from("cowry_payments")
      .insert({
        txRef,
        provider,
        status: "INITIALIZING",
        currency,
        amount,
        cowries,
        packageId,
        userId: user.id,
        attemptKey,
        updatedAt: nowIso(),
      })
      .select("id")
      .single();
    if (error) {
      if (error.code === "23505") {
        const { data: raced } = await db
          .from("cowry_payments")
          .select("*")
          .eq("userId", user.id)
          .eq("attemptKey", attemptKey)
          .maybeSingle();
        if (raced?.status === "PENDING" && raced.checkoutUrl) {
          return json({ checkoutUrl: raced.checkoutUrl });
        }
        return json({ error: "Payment initialization already in progress.", retryable: true }, 409);
      }
      return json({ error: "Unable to start payment.", retryable: true }, 500);
    }
    paymentRow = data;
  }

  const returnUrl =
    `${SUPABASE_URL}/functions/v1/cowry-payment-callback/${provider.toLowerCase()}` +
    `?tx_ref=${encodeURIComponent(txRef)}&return_to=${encodeURIComponent(returnTo)}`;

  const adapter = provider === "FLUTTERWAVE" ? flutterwave : paystack;
  const result = await adapter.initiate({
    amount,
    currency,
    customerEmail: user.email ?? "",
    customerName: (user.user_metadata?.full_name as string | undefined) ?? user.email ?? "Awalingo User",
    packageId,
    cowries,
    returnUrl,
    txRef,
  });

  if (!result.success || !result.checkoutUrl) {
    await db
      .from("cowry_payments")
      .update({ status: "INIT_FAILED", rawResponse: result.rawResponse ?? null, updatedAt: nowIso() })
      .eq("id", paymentRow.id);
    return json({ error: result.error ?? "Unable to start payment.", retryable: true }, 502);
  }

  await db
    .from("cowry_payments")
    .update({
      status: "PENDING",
      providerRef: result.providerRef,
      checkoutUrl: result.checkoutUrl,
      rawResponse: result.rawResponse ?? null,
      updatedAt: nowIso(),
    })
    .eq("id", paymentRow.id)
    .eq("status", "INITIALIZING");

  return json({ checkoutUrl: result.checkoutUrl });
});
