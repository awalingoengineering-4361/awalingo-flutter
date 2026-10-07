// Mirrors createCowryPaymentReference (neolingo: src/lib/payments/*.ts):
// a short, provider-safe transaction reference derived from the user id
// plus a timestamp and random suffix, prefixed so it's recognizable as ours.
export function createCowryPaymentReference(userId: string): string {
  const userPart = userId.replace(/-/g, "").slice(0, 8);
  const timePart = Date.now().toString(36);
  const randomPart = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
  return `cw${userPart}${timePart}${randomPart}`;
}
