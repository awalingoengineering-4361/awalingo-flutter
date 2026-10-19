# Issue 77: Android push notifications

Status: proposed design for user review; implementation has not started.

## Outcome and agreed scope

Make Profile's “Allow Push Notifications” setting work on Android: explicit
permission request, reliable device registration, alerts while the app is open
or in the background, and safe navigation when an alert is tapped. Keep Supabase
for authentication/data and extend the existing web backend notification events.
The user selected Android first; iOS delivery waits for Apple Developer/APNs setup.

Firebase project `awalingo` (project number `288087666317`) is provisioned on Spark.
Android registration: `1:288087666317:android:10276eb73e6edf69ba7cc4`, package
`com.example.awalingo`, matching the current application ID. Downloaded SDK config
is at `/private/tmp/awalingo-firebase-setup/google-services.json`.
The separate Cloud project `awalingo-native-push` is unused and must not be wired
into this implementation. No billing upgrade, Analytics, Firestore, or Firebase
Authentication is needed. Do not rename the Android package in this change.

## Approach and alternatives

Use an Android-only native Firebase Messaging bridge plus a Dart coordinator.
Firebase Android SDK handles registration/delivery; Kotlin owns background
message validation and notification posting. Flutter owns the account lifecycle,
setting UI, authenticated backend calls, and routing notification taps.

The conventional FlutterFire plugin is simpler across both mobile platforms,
but its current iOS dependency requires iOS 15 while this repository targets iOS
13. An Android-only bridge avoids changing the iOS deployment target or pinning
old Firebase SDKs. OneSignal adds a management provider while still requiring FCM
credentials for Google Android devices. Browser VAPID subscriptions cannot serve
this native app. iOS implementation remains a separate follow-up.

## Boundaries

- Flutter: `lib/services/android_push_service.dart` exposes supported/status,
  enable/disable, auth reconciliation, foreground events and tap events. Wrap
  the platform channel and HTTP API for deterministic tests.
- Android: a small bridge registered from MainActivity and a
  FirebaseMessagingService. Apply Google Services configuration, Firebase
  Android dependencies, Android 13 notification permission, a named notification
  channel, and a monochrome notification icon. Do not install FlutterFire or add
  iOS Firebase initialization in this phase.
- Web backend: a server-only FCM sender, authenticated `/api/push/android` routes,
  and a Prisma migration for native device registrations. Keep existing browser
  push subscriptions and VAPID behavior intact.

## Profile behavior

Do not request permission on launch. Enabling from Profile requests permission
when needed, obtains the current FCM token, and registers it with the backend.
The switch is busy during that operation and becomes on only after permission
and backend registration succeed. Denial, unavailable Play services, missing
server configuration, and network failure produce distinct, actionable states.
Permanent denial/channel blocking offers Android notification settings rather
than repeatedly requesting permission. Reconcile OS status on app resume.

Preserve the existing account-wide `allowPushNotifications` preference, including
its effect on web push; make that account-wide scope clear in the setting copy.
Device permission and registration remain device-specific prerequisites. Enabling
updates the account preference and the current registration together. Disabling
updates the account preference and disables the current registration together.
Do not change the separate in-app or marketing-consent settings.

Disable the local display gate immediately when turning off. If server save fails,
keep local delivery off, show that the account change has not yet saved, and offer
retry. Do not falsely claim all devices have been disabled. A saved local pending
disable must be reconciled before re-enabling delivery after restart.

## Authenticated API and storage

Use the existing Next.js backend, authenticated with the Flutter Supabase access
token. Validate that token with Supabase `auth.getUser`; derive the user ID on the
server and ignore any caller-supplied owner. Do not rely on browser cookies.

`GET /api/push/android?installationId=<uuid>` returns configuration readiness,
account preference and this user's installation status. `PUT` accepts the current
installation UUID and FCM token and enables registration/account preference in a
transaction. `PATCH` disables the account preference/current registration in a
transaction. `DELETE` unregisters the current device during sign-out; it does not
change the account preference for other devices. All mutations are authenticated,
validated, and idempotent. Unsupported/malformed platform data is rejected.

The new `native_push_devices` table contains UUID ID, owner `userId` FK to
`user_profile`, installation UUID, unique FCM token, platform `ANDROID`, enabled
flag, and creation/update timestamps. Enforce uniqueness on owner+installation;
registration replaces that installation's previous token. The same current token
can have only one owner; re-registration after account switch transfers it to the
verified caller and removes its old binding. Treat the opaque token as sensitive:
never return another user's registrations, put tokens in URLs, or log them.

The app accesses this table only through the authenticated API. Migration enables
RLS with no direct anon/authenticated table grants; the trusted backend DB role
performs explicitly owner-scoped operations. FK cascade cleans up deleted users.
All Prisma work must use the repository's npm database scripts. No production DB
command or deployment is part of design approval.

The registration API and Flutter Supabase session must target the same environment.
The existing local Flutter configuration has previously matched the staging
Supabase environment, so verify the environment pairing before device tests;
never silently point a staging session at the production registration API.

## Delivery and ownership

Extend `sendPushToUser` to invoke browser and Android transports independently.
Its current early return when VAPID is missing must not prevent native delivery.
Each transport's failures must not suppress the other or the in-app notification.
Native sends honor the account push preference and the existing caller's marketing
filters, and select only enabled registrations for the intended recipient.

Use FCM HTTP v1 via the server-side Firebase Admin SDK. Credentials remain in the
backend's secret configuration, scoped to project `awalingo`; no private key or
service account credentials go into Flutter, Android resources, git, or logs.
Deployment must provision a sender identity with message-send permission. Missing
credentials report native push as unavailable rather than permitting a switch
that cannot deliver. Service-account/key provisioning and deployment are separate
reviewable setup actions after the implementation is tested.

Send high-priority Android **data messages**, with a bounded TTL, including a
schema version, recipient ID, environment identifier, message identifier, title,
body and internal link. Kotlin validates the persisted local owner, environment
and opt-in gate before displaying anything. Do not include FCM's automatic
`notification` payload: background OS auto-display would bypass those checks.
Only honor supported relative Awalingo routes. No arbitrary external URL launch.

Foreground and background delivery use the same validation/display policy and
notification channel. Repeated delivery of the same message identifier updates
the same Android notification rather than creating duplicate alerts. App listener
registration is single-owner and disposed/reconciled across repeated login cycles.

On token refresh, save the newest token natively and reconcile registration when
an authenticated Flutter session is available. Ignore stale asynchronous results
from a prior user/token generation. Sign-out clears the native owner/display gate
and outstanding app notifications before asynchronous unregister/token deletion.
If offline cleanup cannot reach the server, retries must not delay sign-out or
permit an old account's payload to display locally. On account switch, a newly
registered owner replaces the old token binding. Never read another account's
pending tap or display private payloads for a mismatched recipient/environment.

Permanent invalid/unregistered FCM tokens are pruned individually. Transient errors
are reported without deleting valid registrations. Do not blindly resend after
an ambiguous provider response or add retries that duplicate existing event jobs.
FCM is best-effort; Android force-stop prevents delivery until the user opens the
app again. Test ordinary background/process termination separately from force-stop.

## Tap routing

Use explicit immutable PendingIntents targeting MainActivity. Persist the initial
tap and deliver subsequent taps to Flutter through the bridge. Wait until
Supabase auth and the root navigator are ready, validate recipient/environment,
and route once through the existing notification router. Unknown or unsupported
internal links fall back to the notifications list. Logged-out or wrong-account
taps must not open protected content, and a later login must not replay a previous
account's pending tap. In-app notification unread state continues to come from
Supabase, not an optimistic increment based solely on the push payload.

## Verification and rollout

1. API tests: unauthenticated requests, owner isolation, malformed input,
   environment mismatch, duplicate enable/disable, token rotation, account
   transfer, and repeated unregister. Assert persisted rows and preferences.
2. Sender tests: native/browser fan-out, missing VAPID, missing native credentials,
   existing opt-out filters, invalid-token pruning, transient failure isolation,
   payload ownership/environment, and no accidental retries.
3. Flutter/native tests: allow/deny/revoke, enable-disable-enable on the same user,
   network failure/retry, rapid toggle attempts, stale callbacks, offline sign-out,
   two accounts, token refresh, duplicate delivery and startup/resume tap routing.
4. Android integration: deterministic bridge/API fixtures plus actual OS permission
   and notification tray/tap checks on a Play-services emulator. Test foreground,
   background, process-not-running, and reopen. No production-user broadcast.
5. Real FCM end-to-end: send only to the controlled test installation using the
   same backend sender path; verify receipt and tap, then disable and verify
   suppression, then re-enable and repeat. This gate requires sender credentials
   and the migration/API deployed to the intended test environment.
6. Run `scripts/verify-change` in Flutter and inspect its screenshot/window XML.
   Backend requires `npm run lint:sonar`, lint/type checks, relevant tests and
   build. Preserve unrelated user changes in both repositories.

Produce separate backend/schema and Flutter PRs because they are different repos.
Deploy the migration and compatible backend before enabling the Android feature.
No production schema application, server deployment, paid-service enablement, or
broad notification send is implied by approval of this design. Do not mark issue
77 complete merely because the switch renders or fixture tests pass: report the
real-delivery gate explicitly if credentials/deployment remain unavailable.

## References

- https://firebase.google.com/docs/cloud-messaging/flutter/get-started
- https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- https://github.com/firebase/flutterfire/blob/main/packages/firebase_core/firebase_core/ios/firebase_core.podspec
- https://firebase.google.com/docs/cloud-messaging/android/client
