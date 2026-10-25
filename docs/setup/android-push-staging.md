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
flutter build apk --release --split-per-abi --target=lib/main.dart
```

The ARM64 artifact is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
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
