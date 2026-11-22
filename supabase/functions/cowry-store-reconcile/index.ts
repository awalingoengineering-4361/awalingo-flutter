import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  isGooglePlayConfigured,
  listVoidedPurchases,
} from "../_shared/providers/google-play.ts";
import { reconcileVoidedPurchases } from "../_shared/store-refunds.ts";
import { createReconcileHandler } from "./handler.ts";

// This endpoint has its own server-to-server secret, not a user's access token.
// Deploy with --no-verify-jwt; never use the anon key as its authorization.
Deno.serve(createReconcileHandler(
  () => Deno.env.get("COWRY_STORE_RECONCILE_SECRET"),
  async () => {
    if (!isGooglePlayConfigured()) {
      throw new Error("Google Play not configured");
    }
    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    return await reconcileVoidedPurchases({
      list: listVoidedPurchases,
      reverse: async (txRef) => {
        const { data, error } = await db.rpc("refund_cowry_store_purchase", {
          p_tx_ref: txRef,
          p_provider: "GOOGLE_PLAY",
        });
        if (error || data?.success !== true) {
          throw new Error("Refund transaction failed");
        }
      },
    });
  },
));
