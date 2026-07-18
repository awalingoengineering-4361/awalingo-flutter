# Awalingo Flutter

## Setup

Install dependencies:

```bash
flutter pub get
```

Supabase is configured at build time. Copy the profile for your target without
the `.example` suffix and replace the placeholder key:

```bash
cp config/local.android.example.json config/local.android.json
```

Get the local anonymous key from `supabase status` in the `awalingo-app`
project. Configuration files without `.example` in their name are ignored by
Git.

Start the local Supabase stack from `awalingo-app`, then run Android with:

```bash
flutter run -d emulator-5554 \
  --dart-define-from-file=config/local.android.json
```

The Android emulator reaches services on the host machine through
`10.0.2.2`. For the iOS simulator, use `config/local.ios.example.json`, whose
host address is `127.0.0.1`.

For staging or production, copy `config/hosted.example.json` to a suitably
named ignored file and launch or build with the same
`--dart-define-from-file` option.

The app intentionally has no default Supabase project. It exits at startup
with a clear configuration error when either required value is missing.
