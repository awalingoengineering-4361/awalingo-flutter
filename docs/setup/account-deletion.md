# Account deletion

The profile's Delete account entry opens an in-app confirmation. The user types
DELETE and confirms the consequences. A verified Supabase bearer is sent to
`WEB_BASE_URL/api/account/deletion`; no user ID, service-role credential, or
payment key is supplied by Flutter. Web and mobile use the same server flow.

A 202 response means the deletion request is durably received, not that every
record has already been removed. The device clears its local session and pending
push routing, then displays receipt. The worker removes private data, owned
recordings and Auth, preserves published text without personal attribution, and
minimizes retained payment records. Requests target fulfillment within 30 days.
The final confirmation discloses loss of unused Cowries and that deletion does
not automatically issue a refund.

Sign out and sign in again if the server requests recent authentication; the
server checks actual session age, so refreshing an access token is insufficient.
An uncertain response can retry without creating a second request. If the
account has already been banned or removed by cleanup, use the privacy contact
rather than creating a new account to retry deletion.

## Rollout

1. Review the web/backend repository's `docs/setup/account-deletion.md`.
2. Apply its `20261103140000_account_deletion` migration to staging with the
   repository's approved npm database script. Deploy its API, protected deletion
   processor and web deletion page. Migration is required before the backend
   auth gate is deployed, and before the Edge checkout change below.
3. Deploy this repo's `cowry-payment-initiate` Edge Function. Its service-role
   lookup now blocks pending deletions and fails closed if queue access is missing.
   The migration grants the service role only the queue access it needs. The DB
   also guards new payment inserts and minimizes late settlement payloads.
4. Build Flutter with matching staging configuration, then test disposable
   staging accounts across both clients before approving production rollout.
5. Use the production website's `/delete-account` URL as the Play Console
   deletion-request link after it has been deployed and verified publicly.

Confirm before real production schema/deployment/deletion operations. No server
secrets belong in Flutter config files. Financial retention and externally
managed SECURITY DEFINER RPC authorization require review before production.

## Verification

```bash
flutter test test/services/account_deletion_service_test.dart test/screens/account_deletion_screen_test.dart
node --test supabase/functions/_shared/account-deletion.test.ts
scripts/verify-change
flutter drive -d emulator-5554 --driver=test_driver/account_deletion.dart --target=integration_test/account_deletion_test.dart
```

The driver uses injected fixtures, never a real account. It verifies explicit
confirmation, duplicate-tap protection, receipt, failed response and retry.
Screenshots are written to `build/verification/account-deletion/` and must be
inspected along with the normal emulator-launch screenshot. The backend repo
also has local PostgreSQL cleanup, upload-race and complete service fixtures.
