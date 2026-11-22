import { json } from "../cowry-store-purchase/handler.ts";

export function createReconcileHandler(
  secretValue: () => string | undefined,
  run: () => Promise<unknown>,
) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }
    const secret = secretValue();
    if (!secret || secret.length < 32) {
      return json({ error: "Reconciliation not configured" }, 503);
    }
    if (req.headers.get("Authorization") !== `Bearer ${secret}`) {
      return json({ error: "Unauthorized" }, 401);
    }
    try {
      return json({ success: true, result: await run() });
    } catch {
      console.error("Google Play refund reconciliation incomplete");
      return json(
        { error: "Refund reconciliation incomplete; retry required" },
        503,
      );
    }
  };
}
