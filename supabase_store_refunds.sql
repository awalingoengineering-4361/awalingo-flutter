-- Review and apply separately to each environment before enabling the refund job.
-- No customer refund is issued here: the caller has already read a voided order
-- from Google's authenticated API. This transaction reverses its entitlement.
BEGIN;
CREATE OR REPLACE FUNCTION public.refund_cowry_store_purchase(p_tx_ref text, p_provider text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  payment public.cowry_payments%ROWTYPE;
  balance integer;
BEGIN
  IF p_provider NOT IN ('GOOGLE_PLAY', 'APP_STORE') OR p_provider IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unsupported store provider.');
  END IF;
  SELECT * INTO payment FROM public.cowry_payments WHERE "txRef" = p_tx_ref FOR UPDATE;
  IF NOT FOUND THEN
    -- Google's 30-day feed also contains purchases predating this integration.
    RETURN jsonb_build_object('success', true, 'ignored', true);
  END IF;
  IF payment.provider IS DISTINCT FROM p_provider THEN
    RETURN jsonb_build_object('success', false, 'error', 'Provider mismatch.');
  END IF;
  IF payment.status = 'REFUNDED' THEN
    RETURN jsonb_build_object('success', true, 'alreadyProcessed', true);
  END IF;
  IF payment.status = 'SUCCESSFUL' AND to_jsonb(payment)->>'accountDeletedAt' IS NULL THEN
    IF payment."creditedLedgerId" IS NULL THEN
      RAISE EXCEPTION 'Cannot reverse a successful purchase without its credit ledger';
    END IF;
    -- Match the credit RPC's payment -> profile lock order. A duplicate job,
    -- overlapping scan or concurrent credit cannot add a second reversal.
    PERFORM 1 FROM public.user_profile WHERE "userId" = payment."userId" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase owner profile missing'; END IF;
    INSERT INTO public.cowry_ledger ("userId", "eventType", description, cowry_changed)
    VALUES (payment."userId", 'COWRY_STORE_REFUND', 'Store purchase refunded', -payment.cowries);
    SELECT coalesce(sum(cowry_changed), 0) INTO balance FROM public.cowry_ledger WHERE "userId" = payment."userId";
    -- Preserve debt when purchased cowries were already spent; clamping to zero
    -- would let a refund erase the cost of an already-delivered entitlement.
    UPDATE public.user_profile SET "cowryBalance" = balance WHERE "userId" = payment."userId";
  END IF;
  -- PENDING purchases are now ineligible for the normal credit RPC. Deleted
  -- accounts retain only the minimized financial status, never a new ledger.
  UPDATE public.cowry_payments SET status = 'REFUNDED', "updatedAt" = now() WHERE id = payment.id;
  RETURN jsonb_build_object('success', true, 'cowryBalance', balance);
END;
$$;
REVOKE ALL ON FUNCTION public.refund_cowry_store_purchase(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refund_cowry_store_purchase(text, text) TO service_role;
COMMIT;
