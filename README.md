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
