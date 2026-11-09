# Minimum iOS version — 2026-11-09

Awalingo requires **iOS 15.0 or later**. Devices running iOS 13 or 14 cannot
install this build; their previously installed app is not removed by this change.

Runner's Debug, Release and Profile configurations inherit the iOS 15 minimum
from the Xcode project. The tracked Podfile declares the same platform and raises
older CocoaPods deployment targets to 15.0 without lowering targets that require
a newer version. CocoaPods integration and the lockfile are tracked so clean
checkouts retain these settings. Each Flutter build configuration includes its
matching Pods configuration, including a separate Profile configuration.

This replaces the temporary simulator-only override used during certificate
sharing verification. No command-line deployment override is needed.

## Validation

- `ruby -c ios/Podfile` and `plutil -lint ios/Runner.xcodeproj/project.pbxproj` pass.
- `pod install --project-directory=ios` succeeds without the earlier custom
  Profile configuration warning.
- Resolved Xcode settings: Debug, Release and Profile Runner targets each report
  `IPHONEOS_DEPLOYMENT_TARGET = 15.0`; all five resolved CocoaPods targets report
  15.0 or later.
- The built simulator application's `MinimumOSVersion` is 15.0.
- A normal `flutter drive` run on the disposable iPhone simulator builds and
  passes the certificate fixture's 12 checks plus teardown. This includes real
  PNG generation twice, image-only payloads, retry/cancellation, double-tap
  protection and current recipient details, without a deployment override.
- `scripts/verify-change` passes: 189 tests, one existing skip, 33 existing
  informational analysis findings; Android build/install/launch succeeds. The
  final launch screenshot and UI hierarchy were inspected.
