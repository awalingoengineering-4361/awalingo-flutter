# Android push validation — 2026-10-23

Issue #77 was validated using Firebase project `awalingo`, one dedicated Android
emulator, two disposable local Supabase users, and the actual backend registry
and sender. No production database migration, deployment, user broadcast, or
iOS/APNs setup was performed.

## Real delivery results

- Foreground and background messages appeared in the Android tray. Each actual
  tray tap opened the protected Notifications screen through the app root.
- An ordinary process kill (without force-stop) still allowed receipt; tapping
  the notification reopened the app and reached Notifications.
- Opt-out saved successfully and suppressed the next send. Re-enabling restored
  receipt and navigation. A repeated successful journey also passed.
- A real Firebase token replacement updated the registered token and delivery
  continued. Token values were never printed or captured in screenshots.
- Logging out suppressed delivery. Switching from account A to B required B's
  opt-in; A's registration was removed and A's subsequent send was suppressed.
  B received and opened its own notification.
- Real provider probes with the wrong recipient, environment, schema version,
  absolute link, or missing body were suppressed by the native display gate.
  Sending an identical message identifier twice produced one tray entry.
- Android force-stop suppressed receipt. After reopening and reconciliation,
  a fresh send arrived and opened Notifications. A send issued five seconds
  after reopening was not observed within 25 seconds; the later send passed
  after the app reported enabled. Startup deliberately closes the native gate
  until authenticated registry acknowledgement; immediate delivery during
  reconnection is not guaranteed.
- Logout with the local registration API stopped still cleared the native gate
  and suppressed a subsequent send.

Screenshots were inspected under
`build/verification/android-push/live/`, including real tray alerts and their
Notifications destinations. The local accounts have no notification records,
so the destination correctly showed its empty state.

## Integration defect fixed

The first real registration returned 503 because Prisma's PostgreSQL adapter
cannot deserialize the `void` result of `pg_advisory_xact_lock`. Cast the result
to text while retaining the same transaction-scoped locks. A regression using
the actual Prisma registry failed before this fix and passed afterward.
`npm run test:push-db` now exercises actual enable, disable, and unregister in
addition to SQL constraints, RLS/grants, ownership, and cascade checks. Its
synthetic sender key is generated in memory and never sent to Firebase.

Backend verification after the fix: 941 tests passed / 10 skipped, type-check,
Sonar lint and full lint without errors, local database checks, production build.
Mobile verification: 125 Flutter tests, 7 native JVM tests, 2 connected Android
tests, and the complete build/install/launch verification. Review fixes cover
Android API 24/25 startup/settings compatibility and navigation after an auth
change during an asynchronous vote lookup.

## Provisioning and cleanup

The approved sender is
`awalingo-android-push@awalingo.iam.gserviceaccount.com`, bound to the custom role
`projects/awalingo/roles/awalingoFcmSender` containing only
`cloudmessaging.messages.create`. This matches the
[FCM send API's required IAM permission](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send).
The temporary key was revoked and its local file removed after testing. Local
test users and their registrations were removed, test servers stopped, and the
regular app was restored on the emulator. No private credential is committed
or bundled with Flutter.

Production activation still needs the backend migration and deployment, secure
server credential configuration, and a matching `ANDROID_PUSH_API_ORIGIN` in
the mobile build. The sender identity alone does not activate production push.

## Implementation decisions and tradeoffs

- Ruling: use Git worktree for backend — native worktree tool cannot select that repository — cost if wrong: worktree registration only, no product behavior.
- Task 1: Ruling: author migration SQL without applying — verified loopback DB at port 54322 is stopped and Docker unavailable — cost if wrong: DB constraints/RLS still require local execution before rollout. test:push-db blocked, no remote fallback.
- Ruling: task-done runs from mobile plan workspace with backend npm --prefix — two separate Git histories share one approved plan — cost if wrong: helper range is mobile-only; explicit backend ranges are recorded beside it.
- Task 2: Ruling: use default Node route runtime — cacheComponents rejects explicit runtime export and the repository defaults to Node — cost if wrong: build incompatibility exposed by production build.
- Task 3: Ruling: use GoogleApiAvailabilityLight — Firebase's basement dependency provides this class, avoiding an extra Play services UI dependency — cost if wrong: availability check/build fails, covered by native compilation.
- Task 4: Ruling: account-switch fake returns an owner-scoped B status — original fake incorrectly reused A's registration, unlike the API — cost if wrong: fixture could hide ownership bugs; API scope has separate tests.
- Task 5: Ruling: combine controlled Dart journeys with Android instrumentation — avoids adding production-only test injection methods and tests actual permission/channel/tray boundaries separately — cost if wrong: full provider-to-route linkage still needs the real FCM gate.
- Task 5: Ruling: match Android instrumentation runner to resolved app runtime 1.3.0 — Gradle consistent resolution rejects 1.7.0 beside Flutter integration_test's resolved runtime — cost if wrong: older runner compatibility; real-device tests remain required.
- Final: Ruling: live provider/IAM/deployed environment remain unverified — separate authorization is explicitly required and no sender key exists — cost if wrong: real delivery may expose integration gaps; issue 77 stays open.
- Final: Ruling: iOS/APNs excluded — user explicitly chose Android first — cost if wrong: iOS users still cannot receive native push until that follow-up.

The initially blocked local database and real-provider gates above were later
resolved: the migration was applied locally, constraints and the real Prisma
registry passed, and live FCM receipt/navigation passed on 2026-10-23. Production
deployment remains unperformed. No minor review findings were deferred.
