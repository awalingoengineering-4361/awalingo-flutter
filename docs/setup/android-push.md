# Android push setup and controlled delivery check

Issue 77 uses Firebase project **awalingo** (288087666317), package
`com.example.awalingo`. Android only; iOS/APNs remains separate.
The Android SDK config is public application configuration. Sender private keys
belong only in backend secret storage. Firebase Authentication and Firestore are
not used.

## Deployment order

1. Review and merge the backend registry/sender branch first. Apply its migration
   to the explicitly selected environment using that repository's npm database
   scripts. Production database actions require separate authorization.
2. Provision a Firebase sender identity with only `cloudmessaging.messages.create`
   on project `awalingo`. Store its service-account JSON as backend secret
   `FIREBASE_SERVICE_ACCOUNT_JSON`. Never commit it or put it in Flutter assets.
3. Deploy the compatible backend. With a verified Supabase bearer, GET
   `/api/push/android?installationId=<uuid>` must return the expected Supabase
   hostname and `configured:true`; absent credentials return `configured:false`.
4. Set Flutter `ANDROID_PUSH_API_ORIGIN` to that backend's HTTPS **origin**, and
   rebuild. Its Supabase project must match the backend. A missing origin leaves
   the setting unavailable; there is no guessed production fallback.
5. Enable from Profile, grant Android permission, and complete the controlled
   delivery checks below before rollout. Enabling/disabling changes the existing
   account push preference, including browser push. In-app and marketing consent
   remain separate.

## Sender provisioning

Use the authenticated Awalingo engineering account and project `awalingo`.
The scoped role and sender service account below were created with approval on
2026-10-23. The temporary test key was revoked after the controlled delivery
check. A deployment still needs its own approved secret placement. These
commands create external IAM resources and credentials; execute only with
explicit authorization:

```sh
gcloud services enable fcm.googleapis.com --project=awalingo
gcloud iam roles create awalingoFcmSender --project=awalingo \
  --title='Awalingo FCM sender' --permissions=cloudmessaging.messages.create --stage=GA
gcloud iam service-accounts create awalingo-android-push --project=awalingo \
  --display-name='Awalingo Android push sender'
gcloud projects add-iam-policy-binding awalingo \
  --member=serviceAccount:awalingo-android-push@awalingo.iam.gserviceaccount.com \
  --role=projects/awalingo/roles/awalingoFcmSender
# Use private local permissions and secure server-secret storage; do not print JSON.
gcloud iam service-accounts keys create /private/tmp/awalingo-fcm-sender.json \
  --project=awalingo \
  --iam-account=awalingo-android-push@awalingo.iam.gserviceaccount.com
```

Check for existing resources first and reuse a suitable scoped identity rather
than duplicating it. No billing upgrade is needed by this implementation.
Prefer a short-lived controlled local test before deploying any backend.
Afterward, delete the temporary key/file or explicitly move it to the deployment
secret store and rotate it according to the operator's policy.

## Controlled local check (one emulator only)

The local database migration and `npm run test:push-db` have passed on
`127.0.0.1:54322`; those checks roll back their fixture users. No remote migration
has been run. Start a local backend using its `.env.local`, same loopback Supabase
project, and the approved sender secret loaded privately. Do not copy the
production `.env` into the test environment.

Use `adb reverse tcp:54321 tcp:54321` and `adb reverse tcp:3000 tcp:3000` so both
backend and emulator use the same loopback Supabase hostname. Compile a private
local app configuration with `ANDROID_PUSH_API_ORIGIN=http://127.0.0.1:3000`;
HTTP is accepted only for local debug origins. Preserve the regular app config.
Create two controlled **local** auth accounts; never use a production user list.

Register only the test emulator. Send through `sendAndroidPushToUser(testUserId,
{title,body,link})` from the backend, never a project/topic broadcast or Firebase
console notification payload. Console auto-display would bypass this app's
owner/environment display policy. Keep token and secret values out of captured
logs and screenshots.

Record each outcome:

- Foreground receipt and tap to the correct protected destination.
- Background receipt and tap, with one tray entry per message identifier.
- Ordinary process termination, receipt and reopen. Android force-stop is a
  separate case: reopening is required before FCM can resume.
- Disable: account save succeeds, local gate closes, subsequent send suppressed.
- Re-enable and repeat successful receipt/tap immediately.
- Token replacement and account A→B: binding transfers; A's old messages cannot
  display or route for B. Offline logout clears the local gate and notifications.
- Signed-out, mismatched environment, malformed and absolute-link payloads do
  not open protected content or external navigation.

Fixture tests and a rendering switch are not evidence of actual FCM delivery.
The controlled real-delivery outcomes are recorded in
[Android push validation](android-push-validation.md). Production rollout and
iOS/APNs remain separate steps.

## Verification and rollback

Flutter: `scripts/verify-change`, Kotlin `:app:testDebugUnitTest`, Flutter driver
`test_driver/android_push.dart` / `integration_test/android_push_test.dart`, and
Android `:app:connectedDebugAndroidTest`. Permission/tray/UI evidence goes under
`build/verification/android-push/`. The driver starts with denied notification
permission and tests deny followed by allow; reset only that permission's flags
before running. Use a dedicated emulator, not a user's personal device.

Backend: notification tests, `npm run test:push-db` on loopback only,
`npm run lint:sonar`, `npm run lint`, `npm run type-check`, and `npm run build`.
If a Next dev server was running when its Prisma client was regenerated, restart
it before testing.

To stop native delivery, remove/disable the backend sender secret and disable
native registry rows through an authorized owner-scoped operation. Leave browser
VAPID subscriptions intact. Removing the mobile API origin makes future builds
unavailable; it does not itself revoke existing registrations. Keep the additive
registry schema during rollback; dropping it is unnecessary and destructive.

References: [Firebase Android setup](https://firebase.google.com/docs/android/setup),
[FCM server sending](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk),
[FCM IAM permissions](https://firebase.google.com/docs/projects/iam/permissions).
