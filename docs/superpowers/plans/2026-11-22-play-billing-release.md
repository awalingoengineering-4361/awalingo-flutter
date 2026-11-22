# Google Play billing release fixes

> **For agentic workers:** Use superpowers:executing-plans and test-driven development. Continue the accepted PR #38 review fixes in this worktree.

**Goal:** Make native Cowries checkout safe to retry and prepare an auditable Google Play release.

**Architecture:** A store receipt is the fulfillment identity. The authenticated backend verifies its owner and status, then credits the existing unique payment transaction. The client finishes only credited receipts; unfinished store transactions survive application restarts in the store itself.

**Tech Stack:** Flutter in_app_purchase, Supabase Edge Functions, existing payment RPC.

## Constraints and design decisions

- Keep Paystack for web; use native billing on Android/iOS.
- Never consume a rejected or unfulfilled purchase.
- Fail closed before checkout if the account is deleting, backend configuration is missing, or eligibility cannot be checked. Recheck eligibility during fulfillment. A deletion race leaves the purchase unconsumed for refund/support; do not bypass deletion protections.
- Bind receipts to verified store account IDs. Reject unbound receipts rather than letting the first claimant choose an owner.
- Restrict sandbox/license-test credits to an explicit server-side tester allowlist; never trust a client environment flag.
- Support quantity one initially. Keep multi-quantity disabled in Play Console.
- Preserve credited receipts in memory until store completion succeeds; the store re-delivers unfinished receipts after restart. Serialize callbacks by receipt, and recover after sign-in/resume.
- Final package name, signing key, active store products, deployed backend, refund reconciliation, and installed Play-track purchase testing are release gates. Do not claim submission readiness from emulator tests alone.

## Review focus

1. Account switches while verification or eligibility is in flight.
2. Duplicate callbacks and a response lost after server credit.
3. Completion fails after credit, then retries without double credit.
4. A queued deletion, missing configuration, and unauthorized test receipt.
5. Background fulfillment refreshes only the credited owner's visible balance.

## Task 1: Purchase lifecycle

- [ ] Add regression tests for rejection without consumption, finish retry, duplicate callbacks, repeat purchases, account switching and eligibility denial.
- [ ] Run focused Flutter tests and confirm the new assertions fail for the reviewed defects.
- [ ] Implement owner-aware attempts, serialized receipt handling, bounded HTTP calls, eligibility preflight and recovery events.
- [ ] Re-run focused tests, including modal behavior.

## Task 2: Backend eligibility and verification

- [ ] Extract a request handler with injectable external boundaries and add executable Node TypeScript tests for authorization, deletion, binding, test receipts, quantity and duplicate fulfillment.
- [ ] Confirm failures before implementation, then enforce policy in the deployed entry point and provider metadata.
- [ ] Add backend tests to CI and document server-only configuration and deployment checks.

## Task 3: Android release preparation and verification

- [ ] Replace debug release signing with an ignored upload-key configuration and fail closed when absent.
- [ ] Document package/Firebase/Play App Signing requirements, four product IDs, test scenarios, account deletion and store listing checks.
- [ ] Run scripts/verify-change and backend tests, inspect emulator evidence and obtain a fresh code review.
- [ ] Record unresolved external gates with exact next actions. No live purchase, deployment or submission is performed by local verification.
