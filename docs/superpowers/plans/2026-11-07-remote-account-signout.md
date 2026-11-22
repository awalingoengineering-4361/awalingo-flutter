# Remote account sign-out implementation plan

Goal: a mobile device stops displaying an authenticated account after it has been deleted elsewhere.

Design: validate the current Supabase session against Auth at startup, on foreground resume, and every 30 seconds while foregrounded. Refresh an expired token before checking. Confirmed invalid Auth sessions clear local authentication and the protected navigation stack. Network errors and server outages preserve offline state. Snapshot the exact session token so an old check cannot sign out a newer session or another account. Reuse local deletion sign-out cleanup for push registrations; no production mutation or new backend endpoint.

Alternatives: waiting for automatic refresh leaves a long stale UI window; a new realtime deletion channel adds backend complexity. Foreground Auth validation is the chosen local fix.

- [x] Reproduce missing remote-session reconciliation with real SDK and deterministic HTTP fixtures.
- [x] Add session validation, lifecycle scheduling, guarded local cleanup and signed-out navigation.
- [x] Verify invalid accounts, valid accounts, expired refresh, offline recovery, duplicate checks, and account/token switches.
- [x] Run scripts/verify-change, feature integration and inspect emulator evidence.

## Verification and review

- `scripts/verify-change` passed: 181 tests, one existing conditional skip, Android build/install/launch. Full analysis had 34 existing infos plus four new brace infos that were subsequently removed; focused analysis of all seven changed Dart files returned no issues.
- `flutter test test/services/remote_account_signout_test.dart test/widgets/remote_account_lifecycle_test.dart`: 15 passed. Covers SDK-backed active/invalid sessions, offline recovery, server outage, refresh, duplicate checks, delayed validation/logout/storage events, same/different account replacement, startup, resume, foreground polling, and background cancellation.
- `flutter drive -d emulator-5554 --driver=test_driver/remote_account_signout.dart --target=integration_test/remote_account_signout_test.dart`: startup and resume journeys passed; the foreground timer scenario is covered by deterministic widget time rather than repeated on-device delay. Screenshot at build/verification/remote-account-signout/remote-account-signed-out.png inspected.
- Independent review identified and verified fixes for delayed HTTP logout, internal token refresh, and delayed SDK storage/sign-out event races. No remaining concrete blocker in bounded final review.
- Ruling: preserve cached offline state on timeouts/network/5xx; a device cannot discover remote deletion while disconnected. A definitive Auth rejection clears local authentication and protected navigation. Only frontend code changed; no production deployment, migration, valid-account access, or deletion was performed.

Evidence logs are in /private/tmp/awalingo-remote-signout-{final-verify,final-targeted,changed-analysis,drive}.log. The red race fixtures are retained in /private/tmp/awalingo-remote-signout-{races-red,storage-red}.log.
