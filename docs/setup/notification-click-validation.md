# Notification item navigation — tracker 101

Tapping a general announcement used to push another Notifications list because
the backend defaults its link to `/notifications`. Absent or unsupported links
were silent no-ops. Both the bell and full list now open the complete item in
these cases, showing its title, full selectable message and local date/time.
Existing native destinations still open through the shared router. Native push
taps without a notification record retain their existing list fallback.

Unread items are marked read once, scoped by owner and ID. Failed writes leave
the item unread with retry feedback. Pending opens cancel if the source is
removed, the account changes (including switching away and back), or the target
notification is deleted/cleared. Detail content is hidden after account change.
No backend, migration or RLS policy change is needed.

## Verification

Regression tests first reproduced duplicate-list/no-op taps, repeated read writes,
unhandled read failures, and pending navigation across account changes. The
implementation passed the focused suite and the repository's complete ordered
analysis/test/emulator workflow. Deterministic Android fixtures cover both entry
points and inspect persisted fixture state as well as displayed destinations.

A fresh whole-change review found one pending-open deletion race. Tests reproduce
all three cases before the fix: delayed read then swipe-delete; delayed read then
clear-all; deletion while resolving a linked destination. The active record must
still be present before navigation, including after asynchronous lookup.

Evidence lives under `build/verification/notification-click/` and the standard
`build/verification/android-emulator/`. Light details and dark long-message
screenshots were inspected. Android fixtures use mock HTTP and disposable local
accounts; they do not send requests or modify notifications in production.

## Decisions and limits

- Web-only or unsupported destinations show the full notification record. No
  external website is launched and no native admin interface is invented.
  A web-only action still requires using the website.
- Existing optimistic bulk read/delete error handling and unread-badge polling
  behavior are unchanged. Their independent failure/race behavior remains outside
  tracker 101; the new pending-open deletion race is fixed here.
- The existing bell's asynchronous vote-lookup behavior when its underlying source
  is left is unchanged. The new account/session guard improves ownership checks;
  unrelated source-route behavior remains a separate issue.
- Generated platform configuration files are excluded and restored before final
  commit. Verification does not imply a platform configuration change.

The original emulator's application data was preserved. A disposable AVD used the
already installed Android image. A process-only Android SDK home correction and
ADB restart allowed it to use the established host connection; no user SDK
settings, credentials or production configuration were changed.

## Final results — 2026-11-03

- Focused navigation/read/push regression suite: 31 passed.
- Complete `scripts/verify-change`: analysis completed with 34 existing info
  findings; 159 tests passed, one existing test skipped; Android APK built,
  installed and launched. The screenshot was inspected.
- Android notification runner: 27 successful checks including teardown. Both
  bell and list flows, immediate repeats, failures/retry, ownership changes,
  deletion during read or destination lookup, and dark long text passed.
- The sole fresh code review identified one Important deletion race; all three
  deterministic deletion regressions failed before the fix and pass afterward.
  No deferred minor findings were reported; no second review was dispatched.

The final checks target a dedicated emulator serial (emulator-5580). The private
ADB selector filters the real device inventory to that serial and delegates all
commands to the installed ADB; it does not fabricate results. Existing emulator
installations and application data were preserved.

## Installable artifact

Built the normal `lib/main.dart` ARM64 release APK using
`--dart-define-from-file=config/production.json`. The selected Supabase, website
and push origins were checked against the production configuration. This exact
APK installed and cold-launched successfully on emulator-5580; its normal
onboarding screenshot was inspected. It contains no fixture entry point.

Artifact: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
SHA-256: `11d741aa909c7313f1671ada42a89c18f15fa4acad57bad0a38a2b47dde785f1`.
This is a production-configured build; building it does not publish a store release.
