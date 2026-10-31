# Android staging push — 2026-10-25

The staging push API is deployed at
https://awalingo-push-staging.vercel.app. The separate API authenticates Supabase
bearer tokens while the staging website keeps its Vercel protection.

Add this line to the ignored `.env` used when building Flutter:

```dotenv
ANDROID_PUSH_API_ORIGIN=https://awalingo-push-staging.vercel.app
```

Use the matching staging Supabase project
`cmcuzyqkwmprlwmdviys.supabase.co`. Rebuild and install the app: an older APK with
an empty API origin will continue to show push as unavailable. The API origin is
public configuration; Firebase sender credentials belong only on the server.

```sh
scripts/verify-change
flutter build apk --debug --target=lib/main.dart --dart-define-from-file=config/staging.json
```

The current staging artifact is `build/app/outputs/flutter-apk/app-debug.apk`.
Staging verification now uses debug mode: release startup requires the production
config documented in the README. The release results below describe the older
staging activation build and are retained as historical verification evidence.
This build uses staging data. Actual production and iOS/APNs rollout are separate.

Verification passed 129 Flutter tests and the normal emulator build, install,
and launch; the screenshot was inspected. A disposable staging account also
passed the actual Profile toggle, remote device registration, foreground and
background FCM receipt, tray taps opening Notifications, disabling suppressing a
send, and re-enabling restoring delivery. Test account and device data were
removed and the temporary verification key was revoked. Screenshots are under
`build/verification/android-push/staging/` in the isolated task worktree.

The backend branch records API deployment settings and verification in
`docs/setup/staging-push-api.md`. Its HTTP boundary test verifies authentication
and the absence of website, send, secret-file, and framework image routes.
