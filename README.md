# Awalingo Flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Development workflow

Install the repository's tracked Git hooks once per clone:

```bash
scripts/install-git-hooks.sh
```

Start every standalone change from a clean working tree:

```bash
scripts/start-change awaquiz-stages
```

The command creates `codex/awaquiz-stages`. Commits directly to `main` or
`master` are blocked by the pre-commit hook.

### Staging and production configuration

Keep environment settings in `config/staging.json` and
`config/production.json`. Both files use these fields:

| Field | Purpose |
| --- | --- |
| `SUPABASE_URL` | Supabase endpoint for the selected environment |
| `SUPABASE_ANON_KEY` | Public Supabase anon or publishable key |
| `WEB_BASE_URL` | Website URL for the selected environment |
| `ANDROID_PUSH_API_ORIGIN` | Push API origin connected to the same Supabase environment |

These files may contain public client settings only. Never put Supabase
service-role keys, payment secrets, Firebase service-account credentials, or
signing passwords in them.

The app reads the selected JSON file through Dart compile-time definitions.
Supabase, payment requests/callbacks, profile website links, and Android push
all use that configuration. A selected config must supply all four fields;
use an empty push origin to disable push in development. It never fills missing
fields from `.env`.

Keep a `.env` file present because it remains a declared Flutter asset. For a
fresh checkout, copy `.env.example` to `.env`. Its values are used only for
debug/profile startup without any of these compile-time settings. Selected
JSON values take precedence as a complete set. Private server credentials must
not be placed in `.env` either, because it is bundled with the app.

Run a staging build with:

```bash
flutter run --dart-define-from-file=config/staging.json
```

Run a production build with:

```bash
flutter run --dart-define-from-file=config/production.json
```

Build a production Android App Bundle for Play Store preparation with:

```bash
flutter build appbundle --release \
  --dart-define-from-file=config/production.json
```

The environment is selected at build time. Each installed build uses the
settings it was built with; changing a JSON file does not update an installed
app or a running debug session. Stop and rerun the command after changing
environments; hot reload does not replace compile-time settings.

Release startup rejects `.env` fallback and requires these production origins:
`https://auth.awalingo.org`, `https://www.awalingo.org`, and
`https://awalingo-push-production.vercel.app`. Local HTTP is accepted only in
debug mode; other backend origins must use HTTPS. If production domains change,
update the allowlist in `lib/config/app_config.dart` as well as the JSON config.
This guard runs when the app starts, not during bundle compilation. The bundle
command does not replace release signing, launching and verifying the release
artifact, or the Play Console submission steps.

### Verify a runtime change

Run the complete verification workflow before considering a code change ready:

```bash
scripts/verify-change
```

This runs static analysis, automated tests, and then an Android emulator smoke
check. The smoke check uses an already connected Android emulator or launches
`Pixel_7_Pro_API_34`, installs and launches the debug APK, checks for fatal
runtime output, and writes evidence to
`build/verification/android-emulator/`.

Use `AWALINGO_EMULATOR_ID` to select a different configured Android emulator.
The emulator smoke check confirms startup and runtime stability; important user
journeys still need feature-specific integration tests.

The notification bell has a deterministic Android journey covering repeated
opens, dismissal during requests, read updates, retries, and navigation:

```bash
flutter drive -d emulator-5554 --driver=test_driver/notification_bell.dart --target=integration_test/notification_bell_test.dart
```

It uses controlled HTTP responses and saves a preview screenshot under
`build/verification/notification-bell/`.

### Stacked pull requests

For dependent changes that should be reviewed separately, use GitHub's official
stacked-PR extension:

```bash
gh auth login
gh extension install github/gh-stack
gh stack init codex/domain-layer
gh stack add codex/data-layer
gh stack add codex/ui-layer
gh stack view --json
gh stack submit --auto
```

Each branch is one reviewable layer, based on the branch below it. `gh stack` is
currently a GitHub public-preview feature, requires all branches to live in the
same repository, and may need to be enabled for the repository. If it is not
available, create the same branch chain with Git and set each pull request's base
to its immediate parent branch.

Offline handling has deterministic Android journeys for AwaQuiz, Curator Test,
AwaDiko, voting/jury/translation lounges, word requests, and request history:

```bash
flutter drive -d emulator-5554 --driver=test_driver/offline_recovery.dart --target=integration_test/offline_recovery_test.dart
```

These use controlled HTTP responses through the real screens and services,
including connection loss, server errors, repeated recovery, pagination, and
preserved request input. They do not contact the production backend or disable
the emulator's physical network. Screenshots are saved to
`build/verification/offline-recovery/`.

Quiz-card layout regression coverage (phone/tablet widths and enlarged text):

```bash
flutter drive -d emulator-5554 --driver=test_driver/awaquiz_layout.dart --target=integration_test/awaquiz_layout_test.dart
```

Certificate sharing regression coverage (PNG generation, caption, repeated use,
cancellation, failure/retry, and stale result guards):

```bash
flutter drive -d emulator-5554 --driver=test_driver/certificate_share.dart --target=integration_test/certificate_share_test.dart
```

This renders real certificate PNGs on Android and intercepts the share callback
for deterministic payload assertions. Native chooser behavior is checked
separately without selecting a recipient or sending a message.

To check the real Android chooser, run the following device check and dismiss
both share sheets with Android Back. Do not select a recipient or send the
fixture certificate. It checks that cancellation unlocks sharing for another
attempt.

```bash
flutter drive -d emulator-5554 --driver=test_driver/awaquiz_layout.dart --target=integration_test/certificate_share_native_test.dart
```

Curator role refresh regression coverage (real Menu, test, result, and shell
navigation with controlled HTTP responses):

```bash
flutter drive -d emulator-5554 --driver=test_driver/curator_menu_refresh.dart --target=integration_test/curator_menu_refresh_test.dart
```

Checks both test entry points, Go Home and Back after passing, immediate Menu
reopening, failed tests/rejected promotion, eligibility cancellation twice, and
stale responses. Fixtures assert one attempt/promotion/reward for a pass and do
not contact the production backend. Screenshots are saved to
`build/verification/curator-menu/`.

Curator Test exit regression coverage:

```bash
flutter drive -d emulator-5554 --driver=test_driver/curator_test_exit.dart --target=integration_test/curator_test_exit_test.dart
```

Checks root and nested Menu navigation, repeated cancellation/exit/restart,
system Back, duplicate confirmation requests, and Back during submission using
controlled HTTP fixtures. Abandoned runs assert zero database writes; submission
asserts one attempt and reward. The timeout-during-confirmation race uses the
widget tests' virtual clock and is excluded from the Android run. Screenshots
are saved to `build/verification/curator-exit/`.
