# Android notification icon (#100)

The small push notification icon uses the existing Awalingo speech mark from
`assets/branding/logo-mark-transparent.png`, replacing the placeholder letter A.
Android tints small notification icons using their alpha channel, so these
resources contain white foreground pixels on a transparent background.

The source alpha channel is cropped to its nontransparent bounds, scaled
proportionally with Lanczos resampling to fit a 20dp square, and centered in a
24dp canvas. PNG resources cover mdpi (24px), hdpi (36px), xhdpi (48px), xxhdpi
(72px), and xxxhdpi (96px). The original logo and launcher assets are unchanged.
`PushNotifications` continues to use `R.drawable.ic_stat_awalingo`.

To inspect the actual notification without Firebase credentials, run the existing
Android `:app:connectedDebugAndroidTest` fixture on a disposable Android 13+
emulator. `AndroidPushDeviceTest` posts through the production notification
builder, checks duplicate replacement and account suppression, captures the
notification shade, then taps the notification and cleans up its fixture state.
It writes the screenshot to `/data/local/tmp/awalingo-push-tray.png` on the device.

Verified on 2026-11-03 with Android API 34:

- `scripts/verify-change`: 166 Flutter tests passed, one existing skip; analysis
  reported 34 existing informational findings; Android build/install/launch passed.
- `:app:connectedDebugAndroidTest` with `AndroidPushDeviceTest`: two tests passed.
- Inspected `build/verification/notification-icon/push-tray.png`: the speech mark
  is visible in the actual notification shade and the tray tap opens the app.
- Inspected the launch screenshot and matching UI hierarchy under
  `build/verification/android-emulator/`.

The first launch capture received a transient empty Android UI hierarchy. The
full workflow passed on rerun with a longer launch wait; no app code was changed
for that retry. Firebase delivery is unchanged and was not exercised by this
local notification-rendering check.
