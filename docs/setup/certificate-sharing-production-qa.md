# Certificate sharing and iOS 15 QA — 2026-11-09

Reviewed source: `502b9f1..d3d993c`, comprising the single image-sharing action
and iOS 15 minimum. A fresh independent code review found no actionable defects.
No runtime changes were needed during this QA pass.

## Clean-checkout checks

An isolated checkout of `d3d993c` was built with the required ignored `.env`
asset copied privately from the task checkout. No existing worktree build output
was reused. Production build commands used `config/production.json`.

- `scripts/verify-change`: passed, 189 tests and one existing skip; 33 existing
  informational analysis findings. Android debug build/install/launch passed;
  launch screenshot and UI hierarchy were inspected.
- `flutter build apk --release --dart-define-from-file=config/production.json`:
  passed (80.3 MB).
- `flutter build ios --release --no-codesign
  --dart-define-from-file=config/production.json`: passed (50.8 MB).
- `flutter build ios --profile --no-codesign
  --dart-define-from-file=config/production.json`: passed (60.1 MB).
- Built iOS app metadata reports `MinimumOSVersion = 15.0`. Debug, Release and
  Profile resolved deployment settings were checked in the implementation pass.
- Clean builds left tracked iOS configuration and the Pods lockfile unchanged.
  Flutter generated unrelated macOS CocoaPods includes/Podfile; these were
  excluded from the PRs.

## Native sharing and replay

The device fixture generates and decodes real PNG images twice on Android and
iPhone, validating attachment MIME type, payload shape and anchor bounds. Tests
cover cancellation, retry after render/share failure, rapid double taps, changed
certificate details, disposal/navigation away, and caption copy.

Android's real native chooser was opened/dismissed twice with the certificate
preview visible, and the share button became usable again. In this QA pass,
iOS's real native share sheet also displayed the certificate PNG thumbnail and
file size correctly. The manual iOS cancel/reopen fixture was stopped after
that capture because the local SDK installation has no Simulator GUI app for
clicking Cancel; that fixture is not counted as a passing native cancellation
test. iOS cancellation/retry remains covered by the intercepted device fixture.

## Release limits

WhatsApp, Facebook and Instagram are not installed on the test devices, so their
receiving flows and delivery remain unverified. No messages were sent. This QA
validates these code changes and native handoff; it does not claim every
receiving application accepts the attachment.

The repository's existing Android release configuration uses the debug signing
key. iOS device builds above are unsigned. Neither artifact is asserted to be
store-distributable; production signing remains a separate deployment step.

Logs, independent review notes, and native/launch captures are retained in the
local `certificate-sharing-fix/production-qa` artifact directory.
