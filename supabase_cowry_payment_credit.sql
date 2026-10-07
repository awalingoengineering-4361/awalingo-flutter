-- Run once in the Supabase SQL editor for project cmcuzyqkwmprlwmdviys.
--
-- Atomic credit step for the cowry-payment-callback Edge Function. Mirrors
-- fulfillVerifiedCowryPayment + updateUserCowryBalance from the web app
-- (neolingo: src/lib/payments/fulfillment.ts, src/actions/auth.ts), ported
-- to a single Postgres function so the claim -> ledger insert -> balance
-- recompute sequence is transactional (a single function call is one
-- implicit transaction; Supabase's PostgREST/Edge Function clients have no
-- multi-statement transaction of their own).
--
-- Called only from the Edge Function via the service-role key, with the
-- caller already having verified the transaction against the payment
-- provider (Flutterwave/Paystack) and decided p_status — this function
-- trusts that input and only owns the DB-side idempotency + crediting.
create or replace function public.credit_cowry_payment(
  p_tx_ref text,
  p_status text, -- 'SUCCESSFUL' | 'FAILED' | 'PENDING' | 'FAILED_VERIFICATION'
  p_provider_ref text,
  p_raw_response jsonb
) returns jsonb
language plpgsql
as $$
declare
  claimed record;
  existing record;
  ledger_id integer;
  total integer;
begin
  -- Conditional claim: only a row still PENDING gets updated, mirroring the
  -- original's `updateMany({ where: { id, status: 'PENDING' }, ... })`
  -- race-guard. Whichever caller (user-redirect callback or provider
  -- webhook) arrives first wins the claim; the other is a safe no-op below.
  update public.cowry_payments
  set status = p_status,
      "providerRef" = coalesce(p_provider_ref, "providerRef"),
      "rawResponse" = coalesce(p_raw_response, "rawResponse"),
      "updatedAt" = now()
  where "txRef" = p_tx_ref
    and status = 'PENDING'
  returning * into claimed;

  if claimed is null then
    select * into existing from public.cowry_payments where "txRef" = p_tx_ref;
    if existing is null then
      return jsonb_build_object('success', false, 'error', 'Payment record was not found.');
    end if;
    if existing.status = 'SUCCESSFUL' then
      return jsonb_build_object('success', true, 'alreadyProcessed', true);
    end if;
    return jsonb_build_object(
      'success', false,
      'error', 'Payment already processed with a different outcome.',
      'status', existing.status
    );
  end if;

  if p_status is distinct from 'SUCCESSFUL' then
    return jsonb_build_object(
      'success', false,
      'error', case when p_status = 'PENDING'
        then 'Payment is still pending.'
        else 'Payment verification failed.'
      end
    );
  end if;

  -- No-op update used purely to take this user's row lock for the rest of
  -- the transaction, so concurrent cowry writers can't race the ledger
  -- recompute below — mirrors the original's `increment: 0` lock step.
  update public.user_profile
  set "cowryBalance" = "cowryBalance"
  where "userId" = claimed."userId";

  insert into public.cowry_ledger ("userId", "eventType", description, cowry_changed)
  values (
    claimed."userId",
    'COWRY_TOP_UP',
    claimed.cowries || ' cowries purchased via ' || claimed.provider,
    claimed.cowries
  )
  returning id into ledger_id;

  select coalesce(sum(cowry_changed), 0) into total
  from public.cowry_ledger
  where "userId" = claimed."userId";

  update public.user_profile
  set "cowryBalance" = total
  where "userId" = claimed."userId";

  update public.cowry_payments
  set "creditedLedgerId" = ledger_id
  where id = claimed.id;

  return jsonb_build_object('success', true, 'ledgerId', ledger_id, 'cowryBalance', total);
end;
$$;
