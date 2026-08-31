#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fixture_bin="$project_root/test/workflows/fixtures/bin"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/awalingo-emulator-workflow.XXXXXX")"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_with_fakes() {
  local command_log="$1"
  local device_state="$2"
  local artifact_dir="$3"
  shift 3

  PATH="$fixture_bin:$PATH" \
    AWALINGO_TEST_COMMAND_LOG="$command_log" \
    AWALINGO_TEST_DEVICE_STATE="$device_state" \
    AWALINGO_ADB_BIN="$fixture_bin/adb" \
    AWALINGO_APK_PATH="$test_root/app-debug.apk" \
    AWALINGO_ARTIFACT_DIR="$artifact_dir" \
    AWALINGO_EMULATOR_TIMEOUT_SECONDS=2 \
    AWALINGO_LAUNCH_WAIT_SECONDS=0 \
    "$@"
}

test_verify_change_runs_checks_before_emulator_and_captures_evidence() {
  local command_log="$test_root/verify-change.log"
  local device_state="$test_root/verify-change.device"
  local artifact_dir="$test_root/verify-change-artifacts"
  touch "$device_state"

  run_with_fakes \
    "$command_log" \
    "$device_state" \
    "$artifact_dir" \
    "$project_root/scripts/verify-change" >/dev/null

  flutter_command_count="$(sed -n '/^flutter /p' "$command_log" | wc -l | tr -d ' ')"
  [[ "$flutter_command_count" -eq 3 ]] ||
    fail "verify-change did not run exactly three Flutter phases"
  [[ "$(sed -n '/^flutter /p' "$command_log" | sed -n '1p')" == "flutter analyze --no-fatal-infos" ]] ||
    fail "static analysis was not the first verification phase"
  [[ "$(sed -n '/^flutter /p' "$command_log" | sed -n '2p')" == "flutter test" ]] ||
    fail "unit tests were not the second verification phase"
  [[ "$(sed -n '/^flutter /p' "$command_log" | sed -n '3p')" == "flutter build apk --debug" ]] ||
    fail "the emulator APK was not built after tests"

  [[ -s "$artifact_dir/screenshot.png" ]] ||
    fail "emulator verification did not capture a screenshot"
  [[ -s "$artifact_dir/window.xml" ]] ||
    fail "emulator verification did not capture the UI hierarchy"
  [[ -f "$artifact_dir/logcat.txt" ]] ||
    fail "emulator verification did not capture logcat"
}

test_emulator_verification_launches_configured_avd_when_needed() {
  local command_log="$test_root/launch.log"
  local device_state="$test_root/launch.device"
  local artifact_dir="$test_root/launch-artifacts"

  AWALINGO_EMULATOR_ID=Test_API_34 run_with_fakes \
    "$command_log" \
    "$device_state" \
    "$artifact_dir" \
    "$project_root/scripts/verify-android-emulator" >/dev/null

  [[ -f "$device_state" ]] ||
    fail "emulator verification did not launch an unavailable emulator"
  sed -n '/^flutter emulators --launch Test_API_34$/p' "$command_log" | grep -q . ||
    fail "emulator verification launched the wrong AVD"
}

test_emulator_verification_fails_on_fatal_app_log() {
  local command_log="$test_root/fatal.log"
  local device_state="$test_root/fatal.device"
  local artifact_dir="$test_root/fatal-artifacts"
  touch "$device_state"

  if AWALINGO_TEST_LOGCAT='E/flutter: Unhandled Exception: verification failure' \
    run_with_fakes \
      "$command_log" \
      "$device_state" \
      "$artifact_dir" \
      "$project_root/scripts/verify-android-emulator" >/dev/null 2>&1; then
    fail "emulator verification ignored a fatal Flutter log"
  fi
}

test_emulator_verification_tolerates_stale_accessibility_hierarchy() {
  local command_log="$test_root/stale-hierarchy.log"
  local device_state="$test_root/stale-hierarchy.device"
  local artifact_dir="$test_root/stale-hierarchy-artifacts"
  touch "$device_state"

  AWALINGO_TEST_UI_PACKAGE=com.android.chrome run_with_fakes \
    "$command_log" \
    "$device_state" \
    "$artifact_dir" \
    "$project_root/scripts/verify-android-emulator" >/dev/null
}

test_emulator_verification_rejects_app_only_present_in_activity_history() {
  local command_log="$test_root/background-app.log"
  local device_state="$test_root/background-app.device"
  local artifact_dir="$test_root/background-app-artifacts"
  touch "$device_state"

  if AWALINGO_TEST_FOREGROUND_PACKAGE=com.android.chrome run_with_fakes \
    "$command_log" \
    "$device_state" \
    "$artifact_dir" \
    "$project_root/scripts/verify-android-emulator" >/dev/null 2>&1; then
    fail "emulator verification accepted Awalingo only because it remained in activity history"
  fi
}

test_verify_change_runs_checks_before_emulator_and_captures_evidence
test_emulator_verification_launches_configured_avd_when_needed
test_emulator_verification_fails_on_fatal_app_log
test_emulator_verification_tolerates_stale_accessibility_hierarchy
test_emulator_verification_rejects_app_only_present_in_activity_history

printf 'PASS: emulator verification contracts\n'
