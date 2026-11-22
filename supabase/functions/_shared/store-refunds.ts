export async function playTransactionRef(
  purchaseToken: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(purchaseToken),
  );
  const hex = Array.from(
    new Uint8Array(digest),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  return `play-${hex.slice(0, 40)}`;
}

export interface RefundDependencies {
  list(
    page?: string,
  ): Promise<{ purchases: { purchaseToken: string }[]; nextPage?: string }>;
  // The database transaction supplies durable idempotency across overlapping jobs.
  reverse(txRef: string): Promise<void>;
}

/** Scan Google's full available window; no caller-supplied receipt is trusted. */
export async function reconcileVoidedPurchases(
  deps: RefundDependencies,
): Promise<{ processed: number; pages: number }> {
  const seen = new Set<string>();
  let page: string | undefined;
  let processed = 0;
  let pages = 0;
  let failures = 0;
  do {
    const result = await deps.list(page);
    pages++;
    for (const purchase of result.purchases) {
      try {
        if (
          typeof purchase.purchaseToken !== "string" || !purchase.purchaseToken
        ) throw new Error("Invalid voided purchase");
        await deps.reverse(await playTransactionRef(purchase.purchaseToken));
        processed++;
      } catch {
        failures++;
      }
    }
    page = result.nextPage;
    if (page && (seen.has(page) || pages >= 100)) {
      throw new Error("Voided purchase scan incomplete");
    }
    if (page) seen.add(page);
  } while (page);
  if (failures) {
    throw new Error(
      `Refund scan incomplete: ${failures} reversals require retry`,
    );
  }
  return { processed, pages };
}
