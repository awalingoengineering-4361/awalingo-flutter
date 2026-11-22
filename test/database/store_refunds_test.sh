#!/usr/bin/env bash
# An isolated throwaway cluster. Never reads DATABASE_URL or a project .env.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
pg_bin="${AWALINGO_TEST_PG_BIN:-$(pg_config --bindir)}"
fixture_root="$(mktemp -d /tmp/awalingo-refund-db.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$fixture_root/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$fixture_root"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$fixture_root/data" -U postgres -A trust >/dev/null
"$pg_bin/pg_ctl" -D "$fixture_root/data" -l "$fixture_root/server.log" -o "-k $fixture_root -h ''" start >/dev/null
psql_fixture() { "$pg_bin/psql" -X -q -v ON_ERROR_STOP=1 -h "$fixture_root" -U postgres -d postgres "$@"; }
psql_fixture <<'SQL'
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE TABLE public.user_profile ("userId" uuid PRIMARY KEY, "cowryBalance" integer NOT NULL);
CREATE TABLE public.cowry_ledger (id serial PRIMARY KEY, "userId" uuid NOT NULL REFERENCES user_profile("userId"), "eventType" text NOT NULL, description text, cowry_changed integer NOT NULL);
CREATE TABLE public.cowry_payments (id serial PRIMARY KEY, "txRef" text UNIQUE NOT NULL, provider text NOT NULL, "userId" uuid NOT NULL REFERENCES user_profile("userId"), status text NOT NULL, cowries integer NOT NULL, "creditedLedgerId" integer, "providerRef" text, "rawResponse" jsonb, "updatedAt" timestamp, "accountDeletedAt" timestamp);
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
INSERT INTO user_profile VALUES ('00000000-0000-0000-0000-000000000001', 50);
INSERT INTO cowry_ledger ("userId", "eventType", cowry_changed) VALUES
('00000000-0000-0000-0000-000000000001', 'COWRY_TOP_UP', 100),
('00000000-0000-0000-0000-000000000001', 'SPEND', -50);
INSERT INTO cowry_payments ("txRef", provider, "userId", status, cowries, "creditedLedgerId") VALUES
('play-one', 'GOOGLE_PLAY', '00000000-0000-0000-0000-000000000001', 'SUCCESSFUL', 100, 1),
('play-pending', 'GOOGLE_PLAY', '00000000-0000-0000-0000-000000000001', 'PENDING', 50, null),
('paystack-one', 'PAYSTACK', '00000000-0000-0000-0000-000000000001', 'SUCCESSFUL', 50, 1);
SQL
psql_fixture -f "$repo_root/supabase_cowry_payment_credit.sql"
psql_fixture -f "$repo_root/supabase_store_refunds.sql"
# Two workers processing the same refund must serialize at the payment row.
psql_fixture -c "SET ROLE service_role; SELECT refund_cowry_store_purchase('play-one', 'GOOGLE_PLAY');" >"$fixture_root/worker-one.log" &
worker_one=$!
psql_fixture -c "SET ROLE service_role; SELECT refund_cowry_store_purchase('play-one', 'GOOGLE_PLAY');" >"$fixture_root/worker-two.log" &
worker_two=$!
wait "$worker_one"
wait "$worker_two"
psql_fixture <<'SQL'
DO $$ BEGIN
 IF (SELECT "cowryBalance" FROM user_profile LIMIT 1) <> -50 THEN RAISE EXCEPTION 'Refund of spent cowries was not reversed exactly once'; END IF;
 IF (SELECT count(*) FROM cowry_ledger WHERE "eventType" = 'COWRY_STORE_REFUND') <> 1 THEN RAISE EXCEPTION 'Duplicate refund ledger entries'; END IF;
 IF has_function_privilege('authenticated', 'refund_cowry_store_purchase(text,text)', 'EXECUTE') OR has_function_privilege('anon', 'refund_cowry_store_purchase(text,text)', 'EXECUTE') THEN RAISE EXCEPTION 'Clients can refund purchases'; END IF;
END $$;
SELECT refund_cowry_store_purchase('play-pending', 'GOOGLE_PLAY');
DO $$ BEGIN
 IF (SELECT status FROM cowry_payments WHERE "txRef" = 'play-pending') <> 'REFUNDED' THEN RAISE EXCEPTION 'Pending purchase still creditable'; END IF;
 IF (SELECT "cowryBalance" FROM user_profile LIMIT 1) <> -50 THEN RAISE EXCEPTION 'Uncredited purchase changed balance'; END IF;
 IF (refund_cowry_store_purchase('paystack-one', 'GOOGLE_PLAY')->>'success')::boolean THEN RAISE EXCEPTION 'Provider mismatch was accepted'; END IF;
 IF (SELECT status FROM cowry_payments WHERE "txRef" = 'paystack-one') <> 'SUCCESSFUL' THEN RAISE EXCEPTION 'Paystack was changed'; END IF;
 IF NOT (refund_cowry_store_purchase('unknown', 'GOOGLE_PLAY')->>'ignored')::boolean THEN RAISE EXCEPTION 'Unrelated store order broke scan'; END IF;
END $$;
INSERT INTO cowry_payments ("txRef", provider, "userId", status, cowries, "creditedLedgerId", "accountDeletedAt") VALUES
('play-deleted', 'GOOGLE_PLAY', '00000000-0000-0000-0000-000000000001', 'SUCCESSFUL', 100, 1, now());
SELECT refund_cowry_store_purchase('play-deleted', 'GOOGLE_PLAY');
DO $$ BEGIN
 IF (SELECT count(*) FROM cowry_ledger WHERE "eventType" = 'COWRY_STORE_REFUND') <> 1 THEN RAISE EXCEPTION 'Deleted account private ledger was recreated'; END IF;
END $$;
-- Two fresh purchases through the real credit RPC, each retried after success.
INSERT INTO cowry_payments ("txRef", provider, "userId", status, cowries) VALUES
('play-next', 'GOOGLE_PLAY', '00000000-0000-0000-0000-000000000001', 'PENDING', 50),
('play-next-again', 'GOOGLE_PLAY', '00000000-0000-0000-0000-000000000001', 'PENDING', 50);
SELECT credit_cowry_payment('play-next', 'SUCCESSFUL', 'order-next', '{}');
SELECT credit_cowry_payment('play-next', 'SUCCESSFUL', 'order-next', '{}');
SELECT credit_cowry_payment('play-next-again', 'SUCCESSFUL', 'order-again', '{}');
SELECT credit_cowry_payment('play-next-again', 'SUCCESSFUL', 'order-again', '{}');
DO $$ BEGIN
 IF (SELECT "cowryBalance" FROM user_profile LIMIT 1) <> 50 THEN RAISE EXCEPTION 'Repeat credit duplicated or lost money'; END IF;
 IF has_function_privilege('authenticated', 'credit_cowry_payment(text,text,text,jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'Client can authorize wallet credit'; END IF;
END $$;
SELECT refund_cowry_store_purchase('play-next', 'GOOGLE_PLAY');
SELECT refund_cowry_store_purchase('play-next-again', 'GOOGLE_PLAY');
SELECT refund_cowry_store_purchase('play-next-again', 'GOOGLE_PLAY');
DO $$ BEGIN
 IF (SELECT "cowryBalance" FROM user_profile LIMIT 1) <> -50 THEN RAISE EXCEPTION 'Repeat refund duplicated or lost money'; END IF;
 IF (SELECT count(*) FROM cowry_ledger WHERE "eventType" = 'COWRY_STORE_REFUND') <> 3 THEN RAISE EXCEPTION 'Repeat refund ledger count incorrect'; END IF;
END $$;
SQL
printf 'PASS: isolated refund database transactions, concurrency and grants\n'
