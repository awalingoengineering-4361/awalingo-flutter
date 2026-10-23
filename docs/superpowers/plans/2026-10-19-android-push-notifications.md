# Android Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement issue 77 on Android, including opt-in, native alerts, safe taps, and repeatable account/device lifecycle handling.

**Architecture:** Extend the existing Next.js notification sender with FCM and an authenticated device registry. An Android-only Kotlin bridge handles Firebase tokens, background validation and notification posting; a Dart coordinator owns backend registration, Profile state and app navigation. Supabase remains the identity/data authority.

**Tech Stack:** Flutter/Dart, Kotlin, Firebase Android Messaging SDK, Next.js/TypeScript, Prisma/PostgreSQL, Firebase Admin SDK, Vitest/JUnit/Flutter integration tests.

**Spec:** `docs/superpowers/specs/2026-10-19-android-push-notifications-design.md` (approved in this chat).

## Global Constraints

- Android first; no iOS Firebase initialization, deployment-target change or FlutterFire dependency.
- Firebase project `awalingo`, number `288087666317`; package `com.example.awalingo`.
- Android Firebase app `1:288087666317:android:10276eb73e6edf69ba7cc4`.
- Keep Supabase auth/data and existing account-wide `allowPushNotifications` semantics. Preserve in-app and marketing consent behavior.
- Use Android data messages; validate owner/environment/local opt-in before display or tap.
- No tokens, service-account keys or private payloads in logs; no private keys in Flutter/git.
- Backend API and Flutter must use the same Supabase environment; do not silently mix staging and production.
- All Prisma operations use repository npm scripts. Production migration/deployment/sender-identity provisioning require separate authorization after reviewable implementation exists.
- Firebase Spark plan; no billing upgrade, Analytics, Firestore or Firebase Authentication.
- Preserve unrelated changes: Flutter's main checkout has user changes; web checkout currently has modified `supabase/.temp/cli-latest`.

## Review Focus

1. A disable request fails and the app restarts: local alerts stay off until the pending disable is saved (Task 4).
2. Account A's registration response arrives after account B signs in: it cannot re-enable A's native display gate (Task 4).
3. A queued background message belongs to the wrong environment/account: no alert or navigation occurs (Tasks 3 and 5).
4. FCM token rotates while Flutter is absent: native persists the latest token and the next authenticated reconciliation replaces the old binding once (Tasks 1, 3 and 4).
5. Browser push fails or VAPID is absent: eligible Android delivery still runs, and transient FCM errors do not delete valid devices (Task 2).

## Workspace and file map

Mobile worktree: `/Users/sirolad/.codex/worktrees/offline-handling/awalingo-flutter`, branch `codex/android-push-notifications`.
Web source: `/Users/sirolad/Developer/Awalingo/awalingo-app`; use an isolated web worktree on `codex/android-push-backend` from its current remote default branch. Prefer a repository-selectable native worktree tool; if unavailable for that repository, use Git's worktree facility. Preserve the source checkout and its temporary CLI file.

Backend units:
- `prisma/schema.prisma`, `prisma/migrations/<generated>_add_native_push_devices/migration.sql`: registry, constraints, client-access restrictions.
- `src/lib/notifications/android-push-registry.ts`: owner-scoped registration transactions.
- `src/lib/notifications/android-push-auth.ts`: verified Supabase bearer identity and input validation.
- `src/app/api/push/android/route.ts`: GET/PUT/PATCH/DELETE HTTP adapter.
- `src/lib/notifications/android-push.ts`: FCM configuration, payloads, fan-out and invalid-token pruning.
- `src/lib/notifications/push.ts`: browser/native orchestration; preserve browser implementation.
- `src/lib/notifications/__tests__/`: registry, auth, sender and fan-out tests; route tests beside the route.
- `scripts/test-native-push-db.ts`, `package.json`: local-only database invariant checks and dependency/scripts.

Mobile units:
- `android/app/google-services.json`, Android Gradle files and manifest: Firebase resources and messaging registration.
- `android/app/src/main/kotlin/com/example/awalingo/push/PushPolicy.kt`: pure payload/gate validation and identity mapping.
- `.../push/PushStore.kt`: private native preferences for owner/environment/opt-in/pending token/tap.
- `.../push/PushNotifications.kt`: channel, OS status, posting and immutable intents.
- `.../push/AwalingoMessagingService.kt`: Firebase callbacks and event dispatch.
- `.../push/AndroidPushBridge.kt`, `MainActivity.kt`: method/event channels, permission result and launch intents.
- `android/app/src/main/res/drawable/ic_stat_awalingo.xml`: monochrome notification asset.
- `android/app/src/test/kotlin/com/example/awalingo/push/`: policy/store/dispatch tests.
- `lib/services/android_push_platform.dart`, `android_push_api.dart`, `android_push_service.dart`: platform boundary, HTTP boundary, lifecycle/state coordinator.
- `lib/widgets/android_push_setting.dart`: setting UI; keep the already large Profile screen's changes small.
- `lib/main.dart`, `lib/services/auth_provider.dart`, `lib/services/notification_router.dart`, `lib/screens/main/profile_screen.dart`: initialization, logout integration, taps, setting placement.
- `test/services/`, `test/widgets/`, `integration_test/android_push_test.dart`, `test_driver/android_push.dart`: regression coverage.

---

### Task 1: Authenticated, idempotent device registry

**Consumes:** Supabase bearer sessions, user profile and the approved registry design.
**Produces:** `AndroidPushStatus {configured: boolean; accountEnabled: boolean; deviceEnabled: boolean; environment: string}`, `getAndroidPushStatus(userId, installationId)`, `enableAndroidPush(userId, input)`, `disableAndroidPush(userId, installationId)`, `unregisterAndroidPush(userId, installationId)`. Mutators return status, except unregister returns void. `input` contains validated installation UUID and nonempty FCM token, maximum 4096 characters; platform is server-fixed `ANDROID`.

- [ ] Create the isolated backend worktree and confirm its status/base. Read its AGENTS.md and the database-migrations skill/reference. Run existing targeted notification tests as baseline.
- [ ] Write registry/auth/route tests: no or invalid bearer -> 401; malformed UUID/token -> 400; verified caller owns every operation; an attempted body `userId` cannot change ownership; repeated enable yields one device; disable is transactional with the profile; unregister twice is harmless and does not disable other devices; rotated token replaces the old installation binding; the same token switches to the newly authenticated owner.
- [ ] Run `npm run test:run -- src/lib/notifications/__tests__/android-push-registry.test.ts src/lib/notifications/__tests__/android-push-auth.test.ts src/app/api/push/android/__tests__/route.test.ts`; observe meaningful failures before implementing.
- [ ] Add `NativePushDevice` to Prisma: UUID primary key and owner FK/cascade, installation UUID, unique token, platform, enabled, timestamps, unique owner+installation, owner/enabled index. Create the migration with the repo npm migration script against a verified local datasource. If no safe local database exists, author the SQL migration explicitly and record the unapplied state; never default to a remote datasource. Generate the client with `npm run db:generate`; if a Next.js development server is running, tell the user to restart it so it loads the new client.
- [ ] Implement registry transactions and the HTTP adapter. GET takes installationId in query; PUT takes installationId/token JSON; PATCH and DELETE take installationId JSON. Derive user identity with Supabase `auth.getUser` using the bearer token. Missing schema returns actionable 503 status. Missing sender configuration makes GET return configured=false and makes enable return 503; never report enabled success. Never return the token. All queries and deletes scope by the verified owner; token transfer occurs only during authenticated registration.
- [ ] Add `test:push-db` running `dotenv -e .env.local -- tsx scripts/test-native-push-db.ts`. The runner rejects non-loopback datasource hosts before connecting, uses rollback-isolated seeded accounts, and proves FK/uniqueness, idempotent replacement, owner isolation and denial of direct anon/authenticated access. Run only on the verified local database; report a blocked check explicitly if it is unavailable.
- [ ] Re-run targeted tests and `npm run lint:sonar` / `npm run type-check`. Require zero new findings and passing registry tests; resolve existing baseline failures separately rather than mixing cleanup.
- [ ] Commit the cohesive registry/API/migration change. Record whether the migration has actually been applied and to which environment.

### Task 2: Native sender beside existing browser push

**Consumes:** enabled registry rows, existing `PushMessagePayload` and upstream notification consent checks.
**Produces:** `isAndroidPushConfigured(): boolean`, `sendAndroidPushToUser(userId: string, payload: PushMessagePayload): Promise<void>`; existing `sendPushToUser` retains its public signature.

- [ ] Write tests for native send with no VAPID, browser/native failures in either direction, account opt-out, disabled registration, multiple devices, stale-token pruning, transient failure retention and no blind resend after an ambiguous response. Assert no tokens/private credentials in captured logs.
- [ ] Run `npm run test:run -- src/lib/notifications/__tests__/android-push.test.ts src/lib/notifications/__tests__/push-fanout.test.ts`; verify red.
- [ ] Add `firebase-admin` through the package manager. Use a server-only adapter initialized from `FIREBASE_SERVICE_ACCOUNT_JSON`; reject malformed credentials or a project ID other than `awalingo`. The readiness check and API use the same adapter. Keep private credential values out of fixtures and committed environment files.
- [ ] Implement data-only FCM messages: `v='1'`, recipient ID, environment identifier, unique per-send message ID, title, body and supported relative link; Android high priority and TTL 3600 seconds. The environment identifier is the configured Supabase project hostname. Bound input size and validate relative links. Prune only provider-confirmed unregistered/invalid tokens; permission/quota/network failures retain registrations.
- [ ] Refactor `push.ts` into independent transport calls with settled error isolation. Native configuration must not depend on VAPID; existing web setup readiness continues to describe web push. Preserve caller marketing gates and verify account preference within the native sender.
- [ ] Run sender/route tests plus existing notification action tests, `npm run lint:sonar`, type-check and build. Commit the backend sender. Do not deploy or generate a service-account key yet.

### Task 3: Android Firebase bridge and guarded background display

**Consumes:** approved Firebase Android app config and sender payload contract from Task 2.
**Produces:** method channel `awalingo/push`, event channel `awalingo/push/events`. Methods: `status`, `requestPermission`, `getToken`, `setSession`, `deleteToken`, `cancelNotifications`, `getInitialTap`, `openSettings`. Events: `token`, `message`, `tap`. `setSession` takes nullable owner ID, environment hostname and enabled boolean; nullable owner clears pending taps and the display gate.

- [ ] Write Kotlin tests for `PushPolicy.accepts(payload, gate)`: expected owner/environment/version/opt-in accepted; missing, wrong-owner, wrong-environment, malformed or absolute-link payloads rejected. Pin duplicate message IDs to the same notification identity and ensure different IDs remain distinct. Test token rotation persists the newest token without requiring a live Flutter engine.
- [ ] Run `./gradlew :app:testDebugUnitTest` from `android` and verify the new tests fail before adding the bridge.
- [ ] Verify current official compatible Firebase Android BOM and Google Services plugin versions, pin them in Gradle, and copy the verified `google-services.json` from the setup artifact. Keep Firebase Messaging auto-init off until explicit opt-in. Add POST_NOTIFICATIONS and the messaging service without changing the package or iOS files.
- [ ] Implement pure validation in PushPolicy, private native storage in PushStore, and channel/posting/settings logic in PushNotifications. Use channel `awalingo_updates`, an explicit immutable PendingIntent to MainActivity and the monochrome drawable. Validate the native gate before posting, including when Flutter is not running. Repeated messages replace the same notification with only-alert-once behavior.
- [ ] Implement Firebase callbacks, method/event channels and MainActivity wiring. Permission requests return actual OS/channel status; token failures return structured errors. Marshal event-channel emissions onto the main thread. Handle both initial launch and `onNewIntent`; consume each pending tap once. Persist token refresh for the next authenticated Dart reconciliation.
- [ ] Run native tests, `scripts/verify-change`, and inspect the app screenshot/window XML. Verify iOS configuration/deployment files are unchanged. Commit the bridge and build configuration.

### Task 4: Dart lifecycle coordinator and Profile switch

**Consumes:** Task 1 API/status and Task 3 bridge. Configure `ANDROID_PUSH_API_ORIGIN` in Flutter's existing environment loading; absent/invalid origin yields unavailable state. Allow only HTTPS except explicitly local debug loopback/emulator development origins.
**Produces:** `AndroidPushService extends ChangeNotifier` with `state`, `reconcile(User? user)`, `setEnabled(bool enabled)`, `prepareForSignOut()`, `openSettings()`, `dispose()`. UI state includes supported, busy, enabled, blockedByOs, pendingDisable and error. Inject platform/API/auth boundaries in tests. `AndroidPushApi` sends the current Supabase access token and verifies the response environment matches the session's Supabase host.

- [ ] Write tests for grant/deny/revoke, enable-disable-enable, two simultaneous toggle requests, backend failure and retry, restart with pending disable, token rotation, A-to-B account switching during delayed registration, stale responses, repeated login listener ownership, and offline logout. Assert both API outcomes and native display-gate state.
- [ ] Run `flutter test test/services/android_push_service_test.dart test/widgets/android_push_setting_test.dart` and verify red.
- [ ] Implement the platform and API adapters, generating a stable installation UUID through existing uuid/shared-preferences dependencies. Keep token values out of URLs/logs. Persist pending disable before the network request and process it before any automatic re-enable. Serialize mutations and discard asynchronous completions whose auth/token generation is stale.
- [ ] Implement startup/resume/auth reconciliation. Do not request permission on launch; restore a gate only after valid user, OS status, saved preference, environment and current registration reconcile. Native rotates token without Dart; the next authenticated reconciliation replaces its old registration exactly once.
- [ ] Integrate sign-out through AuthNotifier: clear the native gate, pending taps and displayed notifications before starting asynchronous unregister/token deletion. Cleanup failure cannot prevent sign-out. Auth expiry and account switch also close the previous gate immediately.
- [ ] Add `AndroidPushSetting` to Profile, replacing only the disabled push tile. Copy explicitly describes account-wide preference; show busy/save failure and Android-settings recovery states. Keep in-app and marketing controls unchanged. Non-Android remains unsupported without initializing Firebase there.
- [ ] Run targeted tests and `scripts/verify-change`, inspect Profile with deterministic fixtures and the normal launch evidence, then commit lifecycle/UI integration.

### Task 5: Notification taps and deterministic Android journeys

**Consumes:** validated Task 3 tap events and Task 4 current account/environment state.
**Produces:** startup/resume tap routing through the existing notification router, plus reusable integration fixtures and screenshots.

- [ ] Write routing tests: cold start queues one tap until auth/navigation ready; duplicate callbacks route once; logout/account switch discards pending taps; wrong environment is rejected; supported links reach existing destinations; unsupported links fall back to NotificationsScreen; malformed/absolute links cannot launch external navigation.
- [ ] Verify failures, then add a small tap coordinator and connect it to the root navigator in `main.dart`. Extend `notification_router.dart` with an explicit notifications fallback while retaining auth/role checks in destination screens. Reconcile unread counts from Supabase, not synthetic push increments.
- [ ] Add `integration_test/android_push_test.dart` and `test_driver/android_push.dart` with controlled authenticated API and bridge fixtures. Cover a fresh journey and immediate repeated enable-disable-enable, denial/retry, restart, token replacement, A/B ownership, offline logout and foreground/background tap paths. Include Android-native permission/channel/tray checks rather than relying only on a fake Dart service.
- [ ] Run `flutter drive -d emulator-5554 --driver=test_driver/android_push.dart --target=integration_test/android_push_test.dart`; require all deterministic cases pass. Save screenshots under `build/verification/android-push/` and inspect permission/setting/notification/tap destination evidence. Commit tap routing and integration coverage.

### Task 6: Whole-change verification and real FCM delivery gate

**Consumes:** both branches passing their local checks. Requires a sender identity and the registry/API applied to the explicitly selected test environment to verify real delivery.
**Produces:** reviewable backend/mobile changes, repeatable setup instructions, and an honest completion ledger.

- [ ] Run backend `npm run lint:sonar`, `npm run lint`, `npm run type-check`, relevant notification tests and `npm run build`. Run native unit tests and Flutter `scripts/verify-change` in order; inspect fresh screenshot/window XML. Resolve actionable whole-branch code review findings and repeat only affected checks after fixes.
- [ ] Document sender identity setup with only FCM send permissions for `awalingo`, server secret placement, migration order, same-environment API origin, device opt-in and rollback (disable native sender/registration while preserving web delivery). No private key generation, production migration, deployment or broad send occurs without the user's explicit next-step authorization.
- [ ] Prepare the exact migration/deployment/sender-identity actions and test-recipient scope for final approval. The scope is one controlled emulator/device, never all registrations. If a local test server can run the backend sender with approved credentials, prefer it before asking for a deployment.
- [ ] After required setup is authorized and completed, obtain the test installation's token privately, send via the actual backend native sender, and verify foreground receipt/tap, background receipt/tap and ordinary process termination/reopen. Distinguish OS force-stop, which requires reopening before FCM can resume.
- [ ] Disable push and repeat the send to verify local/server suppression; re-enable and repeat successful receipt/tap. Rotate the token and test account switch with controlled accounts; verify old-account messages are suppressed and old token binding is replaced without duplicate alerts. Do not expose tokens or secrets in recorded output.
- [ ] Record each gate as passed or blocked with exact evidence and remaining setup. Never label issue 77 complete if real FCM delivery remains unverified. Produce separate backend and mobile PRs when requested; backend migration/API deployment precedes mobile feature rollout.

## Plan self-review

- Spec sections map to Tasks 1–6; the five Review Focus cases have explicit tests in their owning tasks.
- Channel names, API routes, environment identity and coordinator signatures are consistent across tasks.
- No production mutation or credential provisioning is bundled into implementation approval.
- Native gate validation covers background delivery without Flutter, and account-wide preference changes remain explicit.
- The web source checkout and the Flutter main checkout remain preserved; implementation uses isolated branches.
